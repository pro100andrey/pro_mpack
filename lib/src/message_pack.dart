/// High-level MessagePack API — designed for maximum performance and
/// ergonomics.
///
/// This library provides a high-performance MessagePack [Codec] implementation
/// with support for custom extensions, type groups, and advanced performance
/// optimizations like inline caching and zero-allocation buffer management.
///
/// Key design decisions:
/// - **Direct lookup**: Efficient `Type` → `_Ext` and `extId` → `decoder`
///   lookups via [HashMap].
/// - **Amortized O(1) Polymorphism**: Custom types are cached upon first
///   successful lookup through the fallback hierarchy, eliminating repeated
///   O(N) searches.
/// - **Unified group storage**: Groups register a single decoder-router entry,
///   minimizing dispatch overhead during decoding.
/// - **Hot-path optimization**: The last lookup is cached to avoid rehashing
///   identical types in a row (common in list serialization).
/// - **Zero-Allocation Groups**: Uses buffer rebinding for decoding and direct
///   byte manipulation for encoding to avoid intermediate object allocations.
/// - **ExtId validation**: Range -128..127 enforced at registration time.
library;

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'core/exception.dart';
import 'core/packer.dart';
import 'core/unpacker.dart';
import 'stream/transformer.dart';

// Public type aliases

/// Encodes a value of type [T] into bytes.
///
/// The [packer] parameter allows writing custom encoding logic directly
/// into the stream.
typedef Encoder<T> = void Function(T value, Packer packer);

/// Decodes bytes into a value of type [T].
///
/// The [unpacker] parameter allows reading custom decoding logic directly
/// from the stream. [length] is the byte length of the extension payload.
typedef Decoder<T> = T Function(Unpacker unpacker, int length);

// Main class

/// A high-performance MessagePack codec with custom extension support.
///
/// Supports standard MessagePack types and provides a flexible API for
/// registering custom extensions and grouped types.
///
/// Example:
/// ```dart
/// final mp = MessagePack(
///   extensions: (mp) {
///     mp.register<BigInt>(
///       extId: 1,
///       encoder: (v, p) => p.packString(v.toString()),
///       decoder: (u, l) => BigInt.parse(u.unpackString()!),
///     );
///   },
/// );
///
/// final bytes = mp.pack(BigInt.from(42));
/// final value = mp.unpack<BigInt>(bytes);
/// ```
class MessagePack extends Codec<dynamic, Uint8List> {
  /// Creates a [MessagePack] instance.
  ///
  /// * [extensions]: Optional callback to register custom types during
  ///   initialization.
  /// * [bufferSize]: Initial buffer capacity for the internal [Packer].
  ///   Defaults to 1024.
  /// * [allowOverwrite]: If `true`, allows re-registering the same type or
  ///   extension ID. If `false` (default), throws a [
  ///   MessagePackConfigurationException] on duplicates. Enabling this will
  ///   clear internal caches when a type is re-registered.
  MessagePack({
    void Function(MessagePack mp)? extensions,
    this.bufferSize = 1024,
    bool allowOverwrite = false,
  }) : _allowOverwrite = allowOverwrite {
    extensions?.call(this);
  }

  /// Default buffer capacity for the internal serializer.
  final int bufferSize;

  /// Whether to allow overriding existing type/ID registrations.
  final bool _allowOverwrite;

  // ---- Internal state ----

  /// Flat type → _Ext cache. O(1) for every registered type.
  final Map<Type, _Ext> _types = HashMap();

  /// ExtId → decoder table. Range -128..127 mapped to 0..255.
  final _decoders = List<_Ext?>.filled(256, null);

  /// Cached last lookup result to avoid rehashing identical types in a row.
  Type? _lastType;
  _Ext? _lastExt;

  /// Fallback list for sealed-class types where runtimeType != registered Type
  /// (e.g. BigInt.parse returns _BigIntImpl, not BigInt).
  final List<_Ext> _sealedFallback = [];

  /// Cache for types that are not registered and don't match any fallback.
  /// This prevents repeated O(N) searches for unsupported types.
  final Set<Type> _unhandledTypes = HashSet.identity();

  // Codec converters — created once.
  late final _enc = _MessagePackEncoder(this);
  late final _dec = _MessagePackDecoder(this);

  // Cached single-callbacks for the internal Packer and Unpacker to avoid
  // closure overhead.
  late final EncodeExt _encodeExtCached = _encodeExt;
  late final DecodeExt _decodeExtCached = _decodeExt;

  // Internal index mapping for extId → decoder lookup.
  @pragma('vm:prefer-inline')
  static int _extIndex(int extId) => extId + 128;

  /// Exposes the encoder converter for use in standard Dart APIs.
  @override
  Converter<dynamic, Uint8List> get encoder => _enc;

  /// Exposes the decoder converter for use in standard Dart APIs.
  @override
  Converter<Uint8List, dynamic> get decoder => _dec;

  /// Returns a [StreamTransformer] that decodes a stream of MessagePack bytes
  /// into a stream of objects.
  StreamTransformer<List<int>, dynamic> get streamDecoder =>
      MessagePackStreamTransformer(this);

  // Registration

  /// Registers a custom extension for type [T].
  ///
  /// [extId] must be in the MessagePack range (-128..127) and unique unless
  /// `allowOverwrite` is enabled.
  ///
  /// Example:
  /// ```dart
  /// mp.register<Color>(
  ///   extId: 10,
  ///   encoder: (c, ctx) => ctx.pack(c.value),
  ///   decoder: (d, ctx) => Color(ctx.unpack<int>(d)),
  /// );
  /// ```
  void register<T>({
    required int extId,
    required Encoder<T> encoder,
    required Decoder<T> decoder,
    bool polymorphic = false,
  }) {
    _checkType<T>();
    _checkExtId(extId);

    final ext = _Ext(
      id: extId,
      subId: null,
      canHandle: (v) => v is T,
      encode: (v, p) => encoder(v as T, p),
      decode: (u, l) => decoder(u, l),
    );

    _putType(T, ext, polymorphic: polymorphic);
    _putDecoder(extId, ext);
  }

  /// Registers a group of related types under a single [extId].
  ///
  /// Each type in the group gets a unique `subId` (integer). The `subId` is
  /// automatically prepended to the encoded payload.
  ///
  /// Benefits:
  /// - **ID conservation**: Uses only one extension ID for multiple types.
  /// - **Performance**: Grouped types use the same high-performance routing
  ///   logic as standalone extensions.
  ///
  /// Example:
  /// ```dart
  /// mp.registerGroup(
  ///   extId: 2,
  ///   builder: (g) {
  ///     g.add<Circle>(
  ///       subId: 1,
  ///       encoder: (c, p) => p.packDouble(c.radius),
  ///       decoder: (u, l) => Circle(u.unpackDouble()!),
  ///     );
  ///     g.add<Rectangle>(
  ///       subId: 2,
  ///       encoder: (r, p) => p.packAll([r.w, r.h]),
  ///       decoder: (u, l) {
  ///         final w = u.unpackDouble()!;
  ///         final h = u.unpackDouble()!;
  ///         return Rectangle(w, h);
  ///       },
  ///     );
  ///   },
  /// );
  /// ```
  void registerGroup({
    required int extId,
    required void Function(MessagePackGroup group) builder,
  }) {
    _checkExtId(extId);
    if (!_allowOverwrite && _decoders[_extIndex(extId)] != null) {
      throw MessagePackConfigurationException(
        'Extension id $extId is already registered.',
        'Use a different extId or enable allowOverwrite.',
      );
    }

    // Sub-decoder table filled by the group builder.
    final subs = HashMap<int, _Ext>();

    // Let the caller fill the group.
    builder(MessagePackGroup._(this, extId, subs));

    // Register a single routing decoder for the whole group.
    _decoders[_extIndex(extId)] = _Ext(
      id: extId,
      subId: null,
      canHandle: (_) => false,
      encode: (_, _) => throw StateError('Group encode: use concrete type.'),
      decode: (unpacker, length) {
        if (length == 0) {
          throw const MessagePackFormatException(
            'Empty group payload.',
            'A group extension payload must contain at least a subId.',
          );
        }

        final startOffset = unpacker.offset;
        final subId = unpacker.unpackInt() ?? 0;
        final sub = subs[subId];

        if (sub == null) {
          throw MessagePackConfigurationException(
            'Sub-type $subId not found in group $extId.',
            'Make sure all sub-types are registered via group.add().',
          );
        }

        final readBytes = unpacker.offset - startOffset;
        return sub.decode(unpacker, length - readBytes);
      },
    );
  }

  // Pack / Unpack

  @pragma('vm:prefer-inline')
  Uint8List pack(dynamic value) {
    final s = Packer(
      encodeExt: _encodeExtCached,
      initialBufferSize: bufferSize,
    );
    try {
      s.pack(value);
      return s.takeBytes();
    } finally {
      s.dispose();
    }
  }

  @pragma('vm:prefer-inline')
  T unpack<T>(Uint8List data) =>
      Unpacker(buffer: data, decodeExt: _decodeExtCached).unpack() as T;

  // Single-callback encoder for the Packer

  /// Handles extension encoding for the internal [Packer].
  ///
  /// Implements multiple layers of caching:
  /// 1. **Inline Cache**: Checks if the type is identical to the last one.
  /// 2. **Fast Lookup**: O(1) search in the registered [_types] map.
  /// 3. **Negative Cache**: Quickly skips types known to be unsupported.
  /// 4. **Amortized Fallback**: Searches [_sealedFallback] once and caches the
  ///    result in [_types] for future O(1) lookups.
  @pragma('vm:prefer-inline')
  bool _encodeExt(dynamic value, Packer outPacker) {
    final type = value.runtimeType;

    // Layer 1: Inline cache (identical type).
    if (identical(type, _lastType)) {
      final ext = _lastExt;
      if (ext != null) {
        _groupPayload(ext, value, outPacker);
        return true;
      }

      return false;
    }

    // Layer 2: Fast lookup in HashMap.
    final ext = _types[type];
    _lastType = type;
    _lastExt = ext;

    if (ext != null) {
      _groupPayload(ext, value, outPacker);

      return true;
    }

    // Layer 3: Negative cache.
    if (_unhandledTypes.contains(type)) {
      return false;
    }

    // Layer 4: Polymorphic fallback search with memoization.
    for (final fallback in _sealedFallback) {
      if (fallback.canHandle(value)) {
        // Cache for future O(1) lookups.
        _types[type] = fallback;
        _lastType = type;
        _lastExt = fallback;

        _groupPayload(fallback, value, outPacker);
        return true;
      }
    }

    // Mark as unhandled to skip future searches.
    _unhandledTypes.add(type);

    return false;
  }

  /// Prepares the payload for a group extension.
  ///
  /// Uses a temporary buffer to write the subId and extension payload
  /// seamlessly.
  @pragma('vm:prefer-inline')
  void _groupPayload(_Ext ext, dynamic value, Packer outPacker) {
    outPacker.packExt(ext.id, (p) {
      if (ext.subId != null) {
        p.packInt(ext.subId);
      }

      ext.encode(value, p);
    });
  }

  // Single-callback decoder for the Unpacker

  /// Handles extension decoding for the internal [Unpacker].
  @pragma('vm:prefer-inline')
  dynamic _decodeExt(int extType, int length, Unpacker unpacker) {
    final ext = _decoders[_extIndex(extType)];
    if (ext == null) {
      throw MessagePackConfigurationException(
        'No decoder for extension type $extType.',
        'Register a decoder via MessagePack.register() or registerGroup().',
      );
    }

    return ext.decode(unpacker, length);
  }

  // Internal helpers

  /// Internal type registration logic with duplicate handling and cache
  /// invalidation.
  void _putType(Type type, _Ext ext, {required bool polymorphic}) {
    final oldExt = _types[type];

    if (oldExt != null) {
      if (!_allowOverwrite) {
        throw MessagePackConfigurationException(
          'Type $type is already registered.',
          'Each type can only be registered once.',
        );
      }

      // Cleanup old registration and clear all caches to ensure consistency.
      _sealedFallback.remove(oldExt);
      _unhandledTypes.clear();
      _lastType = null;
      _lastExt = null;
    }

    _types[type] = ext;
    if (polymorphic) {
      _sealedFallback.add(ext);
    }
  }

  /// Internal decoder registration logic.
  void _putDecoder(int extId, _Ext ext) {
    final i = _extIndex(extId);
    if (!_allowOverwrite && _decoders[i] != null) {
      throw MessagePackConfigurationException(
        'Extension id $extId is already registered.',
        'Use a different extId.',
      );
    }

    _decoders[i] = ext;
  }

  /// Validates that the [extId] is within the legal MessagePack range.
  void _checkExtId(int extId) {
    if (extId < -128 || extId > 127) {
      throw MessagePackConfigurationException(
        'Extension id $extId is out of range (-128..127).',
        'Use an id within the MessagePack ext type range.',
      );
    }
  }

  /// Validates that the type [T] can be registered as an extension.
  static void _checkType<T>() {
    if (T == dynamic || T == Object || T == _typeOf<Object?>()) {
      throw MessagePackConfigurationException(
        "Cannot register the broad type '$T'.",
        'Specify a concrete type parameter, e.g. register<MyClass>(...).',
      );
    }

    const builtin = <Type>{
      int,
      String,
      bool,
      double,
      List,
      Map,
      Set,
      Uint8List,
      ByteData,
      DateTime,
      Float,
    };

    if (builtin.contains(T)) {
      throw MessagePackConfigurationException(
        "Type '$T' is a built-in MessagePack type.",
        'Built-in types are handled automatically and cannot be overridden.',
      );
    }
  }

  @pragma('vm:prefer-inline')
  static Type _typeOf<T>() => T;
}

// Group builder — public class, private constructor

/// Builder for grouping multiple types under a single extension ID.
///
/// Instances are created internally by [MessagePack.registerGroup].
class MessagePackGroup {
  MessagePackGroup._(this._mp, this._extId, this._subs);

  final MessagePack _mp;
  final int _extId;
  final Map<int, _Ext> _subs;

  /// Adds type [T] to this group with the given [subId].
  ///
  /// [subId] must be unique within the group. For best performance, use values
  /// between 0 and 127.
  ///
  /// Example:
  /// ```dart
  /// group.add<Circle>(
  ///   subId: 1,
  ///   encoder: (c, ctx) => ctx.pack(c.radius),
  ///   decoder: (d, ctx) => Circle(ctx.unpack<double>(d)),
  /// );
  /// ```
  void add<T>({
    required int subId,
    required Encoder<T> encoder,
    required Decoder<T> decoder,
    bool polymorphic = false,
  }) {
    MessagePack._checkType<T>();

    if (_subs.containsKey(subId)) {
      throw MessagePackConfigurationException(
        'Sub-type id $subId is already registered in group $_extId.',
        'Use a different subId.',
      );
    }

    final ext = _Ext(
      id: _extId,
      subId: subId,
      canHandle: (v) => v is T,
      encode: (v, p) => encoder(v as T, p),
      decode: (u, l) => decoder(u, l),
    );

    _subs[subId] = ext;

    // Register the concrete type in the flat cache for O(1) encoding.
    _mp._putType(T, ext, polymorphic: polymorphic);
  }
}

// Codec adapters

/// Internal converter for encoding objects to MessagePack bytes.
class _MessagePackEncoder extends Converter<dynamic, Uint8List> {
  _MessagePackEncoder(this._mp);

  final MessagePack _mp;

  @override
  @pragma('vm:prefer-inline')
  Uint8List convert(dynamic input) => _mp.pack(input);
}

/// Internal converter for decoding MessagePack bytes to objects.
class _MessagePackDecoder extends Converter<Uint8List, dynamic> {
  _MessagePackDecoder(this._mp);

  final MessagePack _mp;

  @override
  @pragma('vm:prefer-inline')
  dynamic convert(Uint8List input) => _mp.unpack<dynamic>(input);
}

// Internal extension record

/// Internal record representing a registered extension.
class _Ext {
  _Ext({
    required this.id,
    required this.subId,
    required this.encode,
    required this.decode,
    required this.canHandle,
  });

  /// MessagePack extension type id (-128..127).
  final int id;

  /// Sub-type id within a group, or `null` for standalone extensions.
  final int? subId;

  /// Checks if this extension can handle the given value via the `is` operator.
  final bool Function(dynamic) canHandle;

  /// Encodes a value into bytes using a registered [Encoder].
  final void Function(dynamic, Packer) encode;

  /// Decodes bytes into a value using a registered [Decoder].
  final dynamic Function(Unpacker, int) decode;
}

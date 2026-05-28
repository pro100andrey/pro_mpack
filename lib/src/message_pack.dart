/// High-level MessagePack API — designed for maximum performance and
/// ergonomics.
///
/// Key design decisions:
/// - **Direct lookup**: Efficient type → ext and extId → decoder lookups
///   via HashMap.
/// - **Unified group storage**: Groups register a single decoder-router entry,
///   minimizing dispatch overhead during decoding.
/// - **Hot-path optimization**: Last lookup is cached to avoid rehashing
///   identical types in a row (common in list serialization).
/// - **ExtId validation**: Range -128..127 enforced at registration time.
/// - **Private group constructor**: `MessagePackGroup` can only be created via
///   `registerGroup`, preventing misuse.
library;

import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'core/exception.dart';
import 'core/packer.dart';
import 'core/unpacker.dart';

// Public type aliases

/// Encodes a value of type [T] into bytes.
///
/// The [ctx] parameter allows recursive packing of nested objects.
typedef Encoder<T> = Uint8List Function(T value, MessagePackCtx ctx);

/// Decodes bytes into a value of type [T].
///
/// The [ctx] parameter allows recursive unpacking of nested objects.
typedef Decoder<T> = T Function(Uint8List data, MessagePackCtx ctx);

// Context interface — passed to user encoders/decoders

/// Context for recursive MessagePack serialization / deserialization.
///
/// Passed to custom [Encoder] and [Decoder] functions so they can
/// pack/unpack nested objects using the same codec configuration.
abstract interface class MessagePackCtx {
  /// Packs [value] into a MessagePack-encoded [Uint8List].
  Uint8List pack(Object? value);

  /// Packs a sequence of [values] into a single buffer (no wrapping array).
  Uint8List packAll(Iterable<Object?> values);

  /// Unpacks a single value of type [T] from [data].
  T unpack<T>(Uint8List data);

  /// Unpacks all consecutive values from [data].
  List<T> unpackAll<T>(Uint8List data);
}
// Main class

/// A high-performance MessagePack codec with custom extension support.
///
/// ```dart
/// final mp = MessagePack(
///   extensions: (mp) {
///     mp.register<BigInt>(
///       extId: 1,
///       encoder: (v, ctx) => ctx.pack(v.toString()),
///       decoder: (d, ctx) => BigInt.parse(ctx.unpack<String>(d)),
///     );
///   },
/// );
///
/// final bytes = mp.pack(BigInt.from(42));
/// final value = mp.unpack<BigInt>(bytes);
/// ```
class MessagePack extends Codec<Object?, Uint8List> implements MessagePackCtx {
  /// Creates a [MessagePack] instance.
  ///
  /// [extensions] — optional callback to register custom types.
  /// [bufferSize] — initial buffer capacity for serialization (default 1024).
  MessagePack({
    void Function(MessagePack mp)? extensions,
    this.bufferSize = 1024,
  }) {
    extensions?.call(this);
  }

  /// Default buffer capacity for the internal serializer.
  final int bufferSize;

  // ---- Internal state ----

  /// Flat type → _Ext cache. O(1) for every registered type.
  final Map<Type, _Ext> _types = HashMap();

  /// ExtId → decoder. For groups this stores a single _Ext with a routing
  /// decoder, so decoding never needs type checks.
  final Map<int, _Ext> _decoders = HashMap();

  /// Cached last lookup result to avoid rehashing identical types in a row.
  Type? _lastType;
  _Ext? _lastExt;

  /// Fallback list for sealed-class types where runtimeType != registered Type
  /// (e.g. BigInt.parse returns _BigIntImpl, not BigInt).
  final List<_Ext> _sealedFallback = [];

  // Codec converters — created once.
  late final _enc = _MessagePackEncoder(this);
  late final _dec = _MessagePackDecoder(this);

  @override
  Converter<Object?, Uint8List> get encoder => _enc;

  @override
  Converter<Uint8List, Object?> get decoder => _dec;

  // Registration

  /// Registers a custom extension for type [T].
  ///
  /// [extId] must be in the MessagePack range (-128..127) and unique.
  ///
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
  }) {
    _checkType<T>();
    _checkExtId(extId);

    final ext = _Ext(
      id: extId,
      subId: null,
      canHandle: (v) => v is T,
      encode: (v, ctx) => encoder(v as T, ctx),
      decode: (d, ctx) => decoder(d, ctx),
    );

    _putType(T, ext);
    _putDecoder(extId, ext);
  }

  /// Registers a group of related types under a single [extId].
  ///
  /// Each type in the group gets a unique `subId` (integer). The `subId` is
  /// automatically prepended to the encoded payload using standard MessagePack
  /// integer encoding. This ensures that the entire extension payload remains
  /// a valid MessagePack stream, making it easy to decode in any language.
  ///
  /// This approach is ideal for:
  /// - **Organized type families**: Related models that share a namespace.
  /// - **ID conservation**: Reducing the number of extension IDs consumed
  ///   when you have many small types.
  ///
  /// ```dart
  /// mp.registerGroup(
  ///   extId: 2,
  ///   builder: (g) {
  ///     g.add<Circle>(
  ///       subId: 1,
  ///       encoder: (c, ctx) => ctx.pack(c.radius),
  ///       decoder: (d, ctx) => Circle(ctx.unpack<double>(d)),
  ///     );
  ///     g.add<Rectangle>(
  ///       subId: 2,
  ///       encoder: (r, ctx) => ctx.packAll([r.w, r.h]),
  ///       decoder: (d, ctx) {
  ///         final [w as double, h as double] = ctx.unpackAll(d);
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
    if (_decoders.containsKey(extId)) {
      throw MessagePackConfigurationException(
        'Extension id $extId is already registered.',
        'Use a different extId.',
      );
    }

    // Sub-decoder table filled by the group builder.
    final subs = HashMap<int, _Ext>();

    // Let the caller fill the group.
    builder(MessagePackGroup._(this, extId, subs));

    final groupUnpacker = Unpacker.withEmptyBuffer();

    // Register a single routing decoder for the whole group.
    _decoders[extId] = _Ext(
      id: extId,
      subId: null,
      canHandle: (_) => false,
      // Encoding is always done per-concrete-type (via _types), so
      // this encode should never be reached through normal flow.
      encode: (_, _) => throw StateError('Group encode: use concrete type.'),
      decode: (data, ctx) {
        if (data.isEmpty) {
          throw const MessagePackFormatException(
            'Empty group payload.',
            'A group extension payload must contain at least a subId.',
          );
        }

        groupUnpacker.rebind(data);

        final subId = groupUnpacker.unpackInt();
        final sub = subs[subId];
        if (sub == null) {
          throw MessagePackConfigurationException(
            'Sub-type $subId not found in group $extId.',
            'Make sure all sub-types are registered via group.add().',
          );
        }
        return sub.decode(groupUnpacker.remainingBytes, ctx);
      },
    );
  }

  // Pack / Unpack — MessagePackCtx implementation

  @override
  Uint8List pack(Object? value) {
    final s = Packer(
      encodeExt: _encodeExt,
      initialBufferSize: bufferSize,
    );
    try {
      s.pack(value);
      return s.takeBytes();
    } finally {
      s.dispose();
    }
  }

  @override
  Uint8List packAll(Iterable<Object?> values) {
    final s = Packer(
      encodeExt: _encodeExt,
      initialBufferSize: bufferSize,
    );
    try {
      s.packAll(values);
      return s.takeBytes();
    } finally {
      s.dispose();
    }
  }

  @override
  T unpack<T>(Uint8List data) =>
      Unpacker(buffer: data, decodeExt: _decodeExt).unpack() as T;

  @override
  List<T> unpackAll<T>(Uint8List data) {
    final de = Unpacker(buffer: data, decodeExt: _decodeExt);
    final result = <T>[];
    while (de.hasBytesAvailable) {
      result.add(de.unpack() as T);
    }
    return result;
  }

  // Single-callback encoder for the Packer

  ExtEncoded? _encodeExt(Object value) {
    final type = value.runtimeType;

    // Hot-path: same type as last call (very common in list serialization).
    if (identical(type, _lastType)) {
      final ext = _lastExt;
      if (ext != null) {
        return (type: ext.id, data: _groupPayload(ext, value));
      }
      return null;
    }

    final ext = _types[type];
    _lastType = type;
    _lastExt = ext;

    if (ext != null) {
      return (type: ext.id, data: _groupPayload(ext, value));
    }

    // Fallback for sealed classes where runtimeType != registered Type
    // (e.g. BigInt.parse returns _BigIntImpl, not BigInt)
    for (final fallback in _sealedFallback) {
      if (fallback.canHandle(value)) {
        return (type: fallback.id, data: _groupPayload(fallback, value));
      }
    }

    return null;
  }

  Uint8List _groupPayload(_Ext ext, Object? value) {
    final payload = ext.encode(value, this);

    // Non-group extensions — payload is returned as-is.
    final subId = ext.subId;
    if (subId == null) {
      return payload;
    }

    // Group extensions — prefix payload with subId (MessagePack integer).
    // This makes the entire payload a valid MessagePack stream.
    //
    // We pre-allocate payload.length + 9 bytes to avoid buffer reallocation.
    // 9 bytes is the absolute maximum size a MessagePack integer can take
    // (1 byte for the format header + 8 bytes for a 64-bit integer payload).
    final packer = Packer(initialBufferSize: payload.length + 9);
    try {
      packer
        ..packInt(subId)
        // We don't want to pack payload as binary, but append its raw bytes
        // because the encoder already returned them as a packed MessagePack
        // blob.
        ..appendRaw(payload);
      return packer.takeBytes();
    } finally {
      packer.dispose();
    }
  }

  // Single-callback decoder for the Unpacker

  Object? _decodeExt(int extType, Uint8List data) {
    final ext = _decoders[extType];
    if (ext == null) {
      throw MessagePackConfigurationException(
        'No decoder for extension type $extType.',
        'Register a decoder via MessagePack.register() or registerGroup().',
      );
    }
    return ext.decode(data, this);
  }

  // Internal helpers

  void _putType(Type type, _Ext ext) {
    if (_types.containsKey(type)) {
      throw MessagePackConfigurationException(
        'Type $type is already registered.',
        'Each type can only be registered once.',
      );
    }
    _types[type] = ext;
    _sealedFallback.add(ext);
  }

  void _putDecoder(int extId, _Ext ext) {
    if (_decoders.containsKey(extId)) {
      throw MessagePackConfigurationException(
        'Extension id $extId is already registered.',
        'Use a different extId.',
      );
    }
    _decoders[extId] = ext;
  }

  void _checkExtId(int extId) {
    if (extId < -128 || extId > 127) {
      throw MessagePackConfigurationException(
        'Extension id $extId is out of range (-128..127).',
        'Use an id within the MessagePack ext type range.',
      );
    }
  }

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
      encode: (v, ctx) => encoder(v as T, ctx),
      decode: (d, ctx) => decoder(d, ctx),
    );

    _subs[subId] = ext;

    // Register the concrete type in the flat cache for O(1) encoding.
    _mp._putType(T, ext);
  }
}

// Codec adapters

class _MessagePackEncoder extends Converter<Object?, Uint8List> {
  _MessagePackEncoder(this._mp);

  final MessagePack _mp;

  @override
  Uint8List convert(Object? input) => _mp.pack(input);
}

class _MessagePackDecoder extends Converter<Uint8List, Object?> {
  _MessagePackDecoder(this._mp);

  final MessagePack _mp;

  @override
  Object? convert(Uint8List input) => _mp.unpack(input);
}

// Internal extension record

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

  /// Checks if this extension can handle the given value.
  final bool Function(Object) canHandle;

  /// Encodes a value into bytes.
  final Uint8List Function(Object?, MessagePackCtx) encode;

  /// Decodes bytes into a value.
  final Object? Function(Uint8List, MessagePackCtx) decode;
}

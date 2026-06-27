/// Internal extension registry powering the high-level `MessagePack` codec.
///
/// This owns all extension resolution — `Type` → encoder and `extId` → decoder
/// — with the four-layer encode cache (inline cache, flat map, negative cache,
/// and polymorphic fallback memoization), group routing, and cache invalidation
/// on overwrite. It is exposed to the core `Packer`/`Unpacker` only as the bound
/// `encodeExt`/`decodeExt` callbacks, so the hot encode/decode path keeps the
/// same indirection it had when this logic lived on `MessagePack`.
///
/// The class is public so it can be unit-tested directly through the
/// `package:pro_mpack/src/extension_registry.dart` path, but it is intentionally
/// **not exported** from `pro_mpack.dart` — it is not part of the public API.
library;

import 'dart:collection';
import 'dart:typed_data';

import 'package:meta/meta.dart';

import 'core/exception.dart';
import 'core/packer.dart';
import 'core/unpacker.dart';

// Public type aliases

/// Encodes a value of type [T] into bytes.
///
/// The `packer` parameter allows writing custom encoding logic directly
/// into the stream.
typedef Encoder<T> = void Function(T value, Packer packer);

/// Decodes bytes into a value of type [T].
///
/// The `unpacker` parameter allows reading custom decoding logic directly
/// from the stream. [length] is the byte length of the extension payload.
typedef Decoder<T> = T Function(Unpacker unpacker, int length);

/// Owns type→encoder and extId→decoder resolution for `MessagePack`.
///
/// Not part of the public API (not exported from `pro_mpack.dart`); public only
/// so it can be tested directly.
class ExtensionRegistry {
  /// Creates a registry.
  ///
  /// When [allowOverwrite] is `true`, re-registering a type or extension id is
  /// allowed and clears the relevant caches; otherwise duplicates throw a
  /// [MessagePackConfigurationException].
  ExtensionRegistry({bool allowOverwrite = false})
    : _allowOverwrite = allowOverwrite;

  /// Whether to allow overriding existing type/ID registrations.
  final bool _allowOverwrite;

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

  /// The extension-encode callback to hand to a [Packer]. Bound to this
  /// registry so the hot path has no extra indirection.
  late final EncodeExt encodeExt = _encodeExt;

  /// The extension-decode callback to hand to an [Unpacker]. Bound to this
  /// registry so the hot path has no extra indirection.
  late final DecodeExt decodeExt = _decodeExt;

  // Internal index mapping for extId → decoder lookup.
  @pragma('vm:prefer-inline')
  static int _extIndex(int extId) => extId + 128;

  // Test-only views over the otherwise-private cache state. These exist so the
  // resolution caches can be asserted directly, without a full pack/unpack
  // round-trip through `MessagePack`.

  /// Whether [type] is in the negative cache of known-unsupported types.
  @visibleForTesting
  bool isUnhandled(Type type) => _unhandledTypes.contains(type);

  /// Whether [type] has a resolved entry in the flat type cache.
  @visibleForTesting
  bool hasCachedType(Type type) => _types.containsKey(type);

  /// The number of registered polymorphic-fallback extensions.
  @visibleForTesting
  int get fallbackCount => _sealedFallback.length;

  /// The most recently resolved type (the inline cache key), or `null`.
  @visibleForTesting
  Type? get lastResolvedType => _lastType;

  // Registration

  /// Registers a custom extension for type [T].
  void register<T>({
    required int extId,
    required Encoder<T> encoder,
    required Decoder<T> decoder,
    bool polymorphic = false,
  }) {
    _checkType<T>();
    _checkExtId(extId);

    final ext = _makeExt<T>(
      id: extId,
      subId: null,
      encoder: encoder,
      decoder: decoder,
    );

    _putType(T, ext, polymorphic: polymorphic);
    _putDecoder(extId, ext);
  }

  /// Registers a group of related types under a single [extId].
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

  // Single-callback encoder for the Packer

  /// Handles extension encoding for a [Packer].
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

  /// Handles extension decoding for an [Unpacker].
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

  /// Wraps a typed encoder/decoder pair into the internal extension record,
  /// performing the `is`-check and the typed-cast erasure in one place.
  static _Ext _makeExt<T>({
    required int id,
    required int? subId,
    required Encoder<T> encoder,
    required Decoder<T> decoder,
  }) => _Ext(
    id: id,
    subId: subId,
    canHandle: (v) => v is T,
    encode: (v, p) => encoder(v as T, p),
    decode: (u, l) => decoder(u, l),
  );

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
/// Instances are created internally by `MessagePack.registerGroup`.
class MessagePackGroup {
  MessagePackGroup._(this._registry, this._extId, this._subs);

  final ExtensionRegistry _registry;
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
    ExtensionRegistry._checkType<T>();

    if (_subs.containsKey(subId)) {
      throw MessagePackConfigurationException(
        'Sub-type id $subId is already registered in group $_extId.',
        'Use a different subId.',
      );
    }

    final ext = ExtensionRegistry._makeExt<T>(
      id: _extId,
      subId: subId,
      encoder: encoder,
      decoder: decoder,
    );

    _subs[subId] = ext;

    // Register the concrete type in the flat cache for O(1) encoding.
    _registry._putType(T, ext, polymorphic: polymorphic);
  }
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

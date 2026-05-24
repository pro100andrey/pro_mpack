/// High-level MessagePack codec — designed from scratch for ergonomics and
/// performance.
///
/// ## Design principles
///
/// 1. **Single-callback ext encoding** — the core serializer uses a single
///    `EncodeExt` callback instead of the old two-method `ExtEncoder`.
///    This eliminates double hash-lookups at the protocol level.
///
/// 2. **Flat O(1) everything** — all type→ext and extId→decoder lookups
///    are direct HashMap hits. No polymorphic fallback scans.
///
/// 3. **Hot-path cache** — consecutive calls for the same runtime type
///    (e.g. serializing a list of `User`) hit a single-entry cache and
///    skip even the HashMap lookup.
///
/// 4. **Unified decoder map** — groups store a single routing-decoder
///    entry, so decode has zero `is`/`as` type checks.
///
/// 5. **Validation at registration time** — all errors (duplicate types,
///    invalid ext IDs, built-in types) are thrown immediately, including
///    in release mode.
library;

import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'package:pro_binary/pro_binary.dart';

import '../core/exception.dart';
import 'deserializer.dart';
import 'serializer.dart';

// ---------------------------------------------------------------------------
// Public type aliases
// ---------------------------------------------------------------------------

/// User-provided function that encodes a value of type [T] into bytes.
///
/// [ctx] allows recursive packing of nested objects using the same
/// codec configuration.
typedef Encoder<T> = Uint8List Function(T value, MessPackCtx ctx);

/// User-provided function that decodes bytes into a value of type [T].
///
/// [ctx] allows recursive unpacking of nested objects.
typedef Decoder<T> = T Function(Uint8List data, MessPackCtx ctx);

// ---------------------------------------------------------------------------
// Context — passed to user encoders/decoders
// ---------------------------------------------------------------------------

/// Recursive serialization / deserialization context.
///
/// Passed to [Encoder] and [Decoder] callbacks so they can pack/unpack
/// nested objects using the same [MessPack] configuration.
abstract interface class MessPackCtx {
  /// Packs [value] into MessagePack bytes.
  Uint8List pack(Object? value);

  /// Packs multiple [values] into a single buffer (concatenated, no
  /// wrapping array).
  Uint8List packAll(Iterable<Object?> values);

  /// Unpacks a single value of type [T] from [data].
  T unpack<T>(Uint8List data);

  /// Unpacks all consecutive values from [data] into a typed list.
  List<T> unpackAll<T>(Uint8List data);
}

// ---------------------------------------------------------------------------
// Main class
// ---------------------------------------------------------------------------

/// A high-performance MessagePack codec with custom extension support.
///
/// ```dart
/// final mp = MessPack(
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
class MessPack extends Codec<Object?, Uint8List> implements MessPackCtx {
  /// Creates a [MessPack] instance.
  ///
  /// [extensions] — optional callback to register custom types.
  /// [bufferSize] — initial serializer buffer capacity (default 1024).
  MessPack({
    void Function(MessPack mp)? extensions,
    this.bufferSize = 1024,
  }) {
    extensions?.call(this);
  }

  /// Default buffer capacity for the internal serializer.
  final int bufferSize;

  // ---- Internal state ----

  /// Flat `runtimeType → _Ext` map. O(1) for all registered types.
  final Map<Type, _Ext> _types = HashMap();

  /// `extId → _Ext` decoder map. Groups store a single routing decoder.
  final Map<int, _Ext> _decoders = HashMap();

  /// Single-entry hot-path cache — avoids even the HashMap lookup when
  /// serializing consecutive values of the same type (very common for lists).
  Type? _cachedType;
  _Ext? _cachedExt;

  // Codec converters — lazy singletons.
  late final _enc = _MpEncoder(this);
  late final _dec = _MpDecoder(this);

  @override
  Converter<Object?, Uint8List> get encoder => _enc;

  @override
  Converter<Uint8List, Object?> get decoder => _dec;

  // -----------------------------------------------------------------------
  // Registration
  // -----------------------------------------------------------------------

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
    _checkType(T);
    _checkExtId(extId);

    final ext = _Ext(
      id: extId,
      subId: null,
      encode: (v, ctx) => encoder(v as T, ctx),
      decode: (d, ctx) => decoder(d, ctx),
    );

    _putType(T, ext);
    _putDecoder(extId, ext);
  }

  /// Registers a group of related types under a single [extId].
  ///
  /// Each type gets a unique `subId` that is automatically prefixed to the
  /// payload using `varUint` encoding.
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
    required void Function(MessPackGroup group) builder,
  }) {
    _checkExtId(extId);

    if (_decoders.containsKey(extId)) {
      throw MessagePackConfigurationException(
        'Extension id $extId is already registered.',
        'Use a different extId.',
      );
    }

    // Sub-decoder table, populated by the group builder.
    final subs = HashMap<int, _Ext>();
    builder(MessPackGroup._(this, extId, subs));

    // Single routing decoder for the whole group.
    _decoders[extId] = _Ext(
      id: extId,
      subId: null,
      encode: (_, _) {
        throw StateError('Group-level encode must not be called directly.');
      },
      decode: (data, ctx) {
        final reader = BinaryReader(data);
        final subId = reader.readVarUint();
        final sub = subs[subId];
        if (sub == null) {
          throw MessagePackConfigurationException(
            'Sub-type $subId not found in group $extId.',
            'Register it via group.add<T>(subId: $subId, ...).',
          );
        }
        return sub.decode(reader.readRemainingBytes(), ctx);
      },
    );
  }

  // -----------------------------------------------------------------------
  // Pack / Unpack — MessPackCtx implementation
  // -----------------------------------------------------------------------

  @override
  Uint8List pack(Object? value) {
    final s = Serializer(
      encodeExt: _encodeExt,
      bufferSize: bufferSize,
    );
    try {
      s.encode(value);
      return s.takeBytes();
    } finally {
      s.dispose();
    }
  }

  @override
  Uint8List packAll(Iterable<Object?> values) {
    final s = Serializer(
      encodeExt: _encodeExt,
      bufferSize: bufferSize,
    );
    try {
      for (final v in values) {
        s.encode(v);
      }
      return s.takeBytes();
    } finally {
      s.dispose();
    }
  }

  @override
  T unpack<T>(Uint8List data) =>
      Deserializer(data, decodeExt: _decodeExt).decode() as T;

  @override
  List<T> unpackAll<T>(Uint8List data) {
    final de = Deserializer(data, decodeExt: _decodeExt);
    final result = <T>[];
    while (de.hasBytesAvailable) {
      result.add(de.decode() as T);
    }
    return result;
  }

  // -----------------------------------------------------------------------
  // Core callbacks — passed to Serializer / Deserializer
  // -----------------------------------------------------------------------

  /// Single-callback encoder for the [Serializer].
  ///
  /// Returns `(type, data)` for registered types, or `null` for unknown.
  /// Uses [_cachedType] / [_cachedExt] to skip the HashMap on consecutive
  /// same-type calls.
  ExtEncoded? _encodeExt(Object value) {
    final type = value.runtimeType;

    // Hot-path: same type as last call.
    final ext = identical(type, _cachedType)
        ? _cachedExt
        : _lookupAndCache(type);

    if (ext == null) {
      return null;
    }

    final payload = ext.encode(value, this);

    // Standalone extension — no subId prefix.
    final subId = ext.subId;
    if (subId == null) {
      return (type: ext.id, data: payload);
    }

    // Group extension — prefix payload with varUint-encoded subId.
    final prefixed = BinaryWriterPool.withWriter(
      (w) {
        w
          ..writeVarUint(subId)
          ..writeBytes(payload);
        return w.takeBytes();
      },
      payload.length + 5,
    );

    return (type: ext.id, data: prefixed);
  }

  /// Single-callback decoder for the [Deserializer].
  Object? _decodeExt(int extType, Uint8List data) {
    final ext = _decoders[extType];
    if (ext == null) {
      throw MessagePackConfigurationException(
        'No decoder for extension type $extType.',
        'Register it via MessPack.register() or registerGroup().',
      );
    }
    return ext.decode(data, this);
  }

  // -----------------------------------------------------------------------
  // Internal helpers
  // -----------------------------------------------------------------------

  @pragma('vm:prefer-inline')
  _Ext? _lookupAndCache(Type type) {
    final ext = _types[type];
    _cachedType = type;
    _cachedExt = ext;
    return ext;
  }

  void _putType(Type type, _Ext ext) {
    if (_types.containsKey(type)) {
      throw MessagePackConfigurationException(
        'Type $type is already registered.',
        'Each type can only be registered once.',
      );
    }
    _types[type] = ext;
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

  static void _checkExtId(int extId) {
    if (extId < -128 || extId > 127) {
      throw MessagePackConfigurationException(
        'Extension id $extId is out of range (-128..127).',
        'Use an id within the MessagePack ext type range.',
      );
    }
  }

  static void _checkType(Type t) {
    if (t == dynamic || t == Object) {
      throw MessagePackConfigurationException(
        "Cannot register the broad type '$t'.",
        'Specify a concrete type parameter, e.g. register<MyClass>(...).',
      );
    }

    const builtin = {
      int, String, bool, double,
      List, Map, Set,
      Uint8List, ByteData, DateTime, Float,
    };

    if (builtin.contains(t)) {
      throw MessagePackConfigurationException(
        "Type '$t' is a built-in MessagePack type.",
        'Built-in types are handled automatically and cannot be overridden.',
      );
    }
  }
}

// ---------------------------------------------------------------------------
// Group builder — public API, private constructor
// ---------------------------------------------------------------------------

/// Builder for grouping related types under a single extension ID.
///
/// Instances are only created by [MessPack.registerGroup].
class MessPackGroup {
  MessPackGroup._(this._mp, this._extId, this._subs);

  final MessPack _mp;
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
    MessPack._checkType(T);

    if (_subs.containsKey(subId)) {
      throw MessagePackConfigurationException(
        'Sub-type id $subId is already used in group $_extId.',
        'Use a different subId.',
      );
    }

    final ext = _Ext(
      id: _extId,
      subId: subId,
      encode: (v, ctx) => encoder(v as T, ctx),
      decode: (d, ctx) => decoder(d, ctx),
    );

    _subs[subId] = ext;
    _mp._putType(T, ext);
  }
}

// ---------------------------------------------------------------------------
// Codec adapters
// ---------------------------------------------------------------------------

class _MpEncoder extends Converter<Object?, Uint8List> {
  _MpEncoder(this._mp);
  final MessPack _mp;

  @override
  Uint8List convert(Object? input) => _mp.pack(input);
}

class _MpDecoder extends Converter<Uint8List, Object?> {
  _MpDecoder(this._mp);
  final MessPack _mp;

  @override
  Object? convert(Uint8List input) => _mp.unpack(input);
}

// ---------------------------------------------------------------------------
// Internal ext record
// ---------------------------------------------------------------------------

class _Ext {
  _Ext({
    required this.id,
    required this.subId,
    required this.encode,
    required this.decode,
  });

  final int id;
  final int? subId;
  final Uint8List Function(Object?, MessPackCtx) encode;
  final Object? Function(Uint8List, MessPackCtx) decode;
}

/// High-level MessagePack API — redesigned for maximum performance and
/// ergonomics.
///
/// Key design decisions:
/// - **Zero double-lookups**: The core [ExtEncoder] contract is replaced with
///   a single `encodeExt` call that returns `(extId, payload)` in one step.
/// - **Flat O(1) everything**: All type → ext and extId → decoder lookups
///   are direct HashMap hits.
/// - **Unified group storage**: Groups register a single decoder-router entry,
///   so `decodeObject` has no `is` checks or casts.
/// - **Private group constructor**: `MessPackGroup` can only be created via
///   `registerGroup`, preventing misuse.
library;

import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'package:pro_binary/pro_binary.dart';

import 'core/exception.dart';
import 'core/packer.dart';
import 'core/unpacker.dart';

// ---------------------------------------------------------------------------
// Public type aliases
// ---------------------------------------------------------------------------

/// Encodes a value of type [T] into bytes.
///
/// The [ctx] parameter allows recursive packing of nested objects.
typedef Encoder<T> = Uint8List Function(T value, MessPackCtx ctx);

/// Decodes bytes into a value of type [T].
///
/// The [ctx] parameter allows recursive unpacking of nested objects.
typedef Decoder<T> = T Function(Uint8List data, MessPackCtx ctx);

// ---------------------------------------------------------------------------
// Context interface — passed to user encoders/decoders
// ---------------------------------------------------------------------------

/// Context for recursive MessagePack serialization / deserialization.
///
/// Passed to custom [Encoder] and [Decoder] functions so they can
/// pack/unpack nested objects using the same codec configuration.
abstract interface class MessPackCtx {
  /// Packs [value] into a MessagePack-encoded [Uint8List].
  Uint8List pack(Object? value);

  /// Packs a sequence of [values] into a single buffer (no wrapping array).
  Uint8List packAll(Iterable<Object?> values);

  /// Unpacks a single value of type [T] from [data].
  T unpack<T>(Uint8List data);

  /// Unpacks all consecutive values from [data].
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
class MessPack extends Codec<Object?, Uint8List>
    implements MessPackCtx {
  /// Creates a [MessPack] instance.
  ///
  /// [extensions] — optional callback to register custom types.
  /// [bufferSize] — initial buffer capacity for serialization (default 1024).
  MessPack({
    void Function(MessPack mp)? extensions,
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
  /// decoder, so [decodeObject] never needs type checks.
  final Map<int, _Ext> _decoders = HashMap();

  /// Cached last lookup result to avoid double hash on the hot
  /// `extTypeForObject` → `encodeObject` path.
  Type? _lastType;
  _Ext? _lastExt;

  // Codec converters — created once.
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
  /// Each type in the group gets a unique `subId` (0..N). The `subId` is
  /// automatically prepended to the encoded payload:
  /// - `subId < 256` → 1 byte prefix (fast path).
  /// - `subId >= 256` → varUint prefix.
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

    // Sub-decoder table filled by the group builder.
    final subs = HashMap<int, _Ext>();

    // Let the caller fill the group.
    builder(MessPackGroup._(this, extId, subs));

    // Register a single routing decoder for the whole group.
    _decoders[extId] = _Ext(
      id: extId,
      subId: null,
      // Encoding is always done per-concrete-type (via _types), so
      // this encode should never be reached through normal flow.
      encode: (_, _) => throw StateError('Group encode: use concrete type.'),
      decode: (data, ctx) {
        final reader = BinaryReader(data);
        final subId = reader.readVarUint();
        final sub = subs[subId];
        if (sub == null) {
          throw MessagePackConfigurationException(
            'Sub-type $subId not found in group $extId.',
            'Make sure all sub-types are registered via group.add().',
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

  // -----------------------------------------------------------------------
  // Single-callback encoder for the Packer
  // -----------------------------------------------------------------------

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

    return null;
  }

  Uint8List _groupPayload(_Ext ext, Object? value) {
    final payload = ext.encode(value, this);

    // Non-group extensions — payload is returned as-is.
    final subId = ext.subId;
    if (subId == null) {
      return payload;
    }

    // Group extensions — prefix payload with subId (varUint encoded).
    return BinaryWriterPool.withWriter(
      (w) {
        w
          ..writeVarUint(subId)
          ..writeBytes(payload);
        return w.takeBytes();
      },
      payload.length + 5,
    );
  }

  // -----------------------------------------------------------------------
  // Single-callback decoder for the Unpacker
  // -----------------------------------------------------------------------

  Object? _decodeExt(int extType, Uint8List data) {
    final ext = _decoders[extType];
    if (ext == null) {
      throw MessagePackConfigurationException(
        'No decoder for extension type $extType.',
        'Register a decoder via MessPack.register() or registerGroup().',
      );
    }
    return ext.decode(data, this);
  }

  // -----------------------------------------------------------------------
  // Internal helpers
  // -----------------------------------------------------------------------

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

  void _checkExtId(int extId) {
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
// Group builder — public class, private constructor
// ---------------------------------------------------------------------------

/// Builder for grouping multiple types under a single extension ID.
///
/// Instances are created internally by [MessPack.registerGroup].
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
        'Sub-type id $subId is already registered in group $_extId.',
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

    // Register the concrete type in the flat cache for O(1) encoding.
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
// Internal extension record
// ---------------------------------------------------------------------------

class _Ext {
  _Ext({
    required this.id,
    required this.subId,
    required this.encode,
    required this.decode,
  });

  /// MessagePack extension type id (-128..127).
  final int id;

  /// Sub-type id within a group, or `null` for standalone extensions.
  final int? subId;

  /// Encodes a value into bytes.
  final Uint8List Function(Object?, MessPackCtx) encode;

  /// Decodes bytes into a value.
  final Object? Function(Uint8List, MessPackCtx) decode;
}

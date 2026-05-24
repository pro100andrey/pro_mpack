/// High-level MessagePack API with a builder-style interface for extensions.
library;

import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'package:pro_binary/pro_binary.dart';

import 'core/exception.dart';
import 'core/packer.dart';
import 'core/unpacker.dart';

/// A function type that encodes a value of type [T] into bytes.
typedef Encoder<T> = Uint8List Function(T value, MessagePackContext context);

/// A function type that decodes bytes into a value of type [T].
typedef Decoder<T> = T Function(Uint8List data, MessagePackContext context);

/// A context for MessagePack serialization and deserialization.
///
/// This interface is passed to custom encoders and decoders, allowing them
/// to recursively pack and unpack nested objects using the same configuration.
abstract interface class MessagePackContext {
  /// Packs [value] into a MessagePack-encoded [Uint8List].
  Uint8List pack<T>(T value);

  /// Packs a sequence of [values] into a single MessagePack-encoded
  /// [Uint8List].
  Uint8List packAll<T>(Iterable<T> values);

  /// Unpacks a single value of type [T] from the provided [data].
  T unpack<T>(Uint8List data);

  /// Unpacks all consecutive values from [data] into a list of type [T].
  List<T> unpackAll<T>(Uint8List data);
}

/// A class for high-level MessagePack operations with custom extension support.
///
/// This implementation is optimized for maximum performance using a flat O(1)
/// lookup for all registered types, including grouped extensions.
class MessagePack extends Codec<dynamic, Uint8List>
    implements MessagePackContext {
  /// Creates a [MessagePack] instance.
  MessagePack({
    void Function(MessagePack messagePack)? extensions,
    this.defaultBufferSize = 1024,
  }) {
    extensions?.call(this);
  }

  /// The default buffer size for serialization.
  final int defaultBufferSize;

  // Flat cache: Type -> Instruction for packing (O(1) for all types).
  final Map<Type, _Ext> _typeCache = HashMap();

  // Decoder lookup: extId -> _Ext (single) or Map<int, _Ext> (group).
  final Map<int, Object> _idToExt = HashMap();

  late final _encoder = _MPackEncoder(this);
  late final _decoder = _MPackDecoder(this);

  @override
  Converter<Object?, Uint8List> get encoder => _encoder;

  @override
  Converter<Uint8List, Object?> get decoder => _decoder;

  /// Registers a custom extension for type [T].
  void register<T>({
    required int extId,
    required Encoder<T> encoder,
    required Decoder<T> decoder,
  }) {
    assert(T != dynamic && T != Object, 'Specify a concrete type <T>.');
    _validateType(T);
    final ext = _Ext(
      extId,
      null,
      (v, ctx) => encoder(v as T, ctx),
      (d, ctx) => decoder(d, ctx),
    );
    _add(extId, T, ext);
  }

  /// Registers a group of related types under a single [extId].
  void registerGroup({
    required int extId,
    required void Function(MessagePackGroup group) builder,
  }) {
    if (_idToExt.containsKey(extId)) {
      throw MessagePackConfigurationException(
        'Extension with id $extId already registered.',
        '',
      );
    }

    builder(MessagePackGroup(this, extId));
  }

  void _add(int id, Type type, _Ext ext) {
    if (_typeCache.containsKey(type)) {
      throw MessagePackConfigurationException(
        'Type $type already registered.',
        '',
      );
    }
    // Only check for extId collisions for non-group extensions.
    if (ext.subId == null && _idToExt.containsKey(id)) {
      throw MessagePackConfigurationException(
        'Extension with id $id already registered.',
        '',
      );
    }

    _typeCache[type] = ext;

    if (ext.subId == null) {
      _idToExt[id] = ext;
    }
  }

  void _validateType(Type t) {
    const builtin = {
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

    if (builtin.contains(t)) {
      throw MessagePackConfigurationException("Type '$t' is built-in.", '');
    }
  }

  @override
  Uint8List pack<T>(T value) {
    final s = Packer(
      encodeExt: _encodeExt,
      initialBufferSize: defaultBufferSize,
    );
    try {
      s.pack(value);
      return s.takeBytes();
    } finally {
      s.dispose();
    }
  }

  @override
  Uint8List packAll<T>(Iterable<T> values) {
    final s = Packer(
      encodeExt: _encodeExt,
      initialBufferSize: defaultBufferSize,
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
    final res = <T>[];
    while (de.hasBytesAvailable) {
      res.add(de.unpack() as T);
    }
    return res;
  }

  // --- Single-callback encoder for the Packer ---

  ExtEncoded? _encodeExt(Object value) {
    final ext = _typeCache[value.runtimeType];
    if (ext == null) {
      return null;
    }

    final payload = ext.encoder(value, this);
    final subId = ext.subId;
    if (subId == null) {
      return (type: ext.id, data: payload);
    }

    if (subId >= 0 && subId < 128) {
      final result = Uint8List(payload.length + 1);
      result[0] = subId;
      result.setRange(1, result.length, payload);
      return (type: ext.id, data: result);
    }

    // For groups, prefix the payload with the subId.
    return (type: ext.id, data: BinaryWriterPool.withWriter(
      (w) {
        w
          ..writeVarUint(subId)
          ..writeBytes(payload);
        return w.takeBytes();
      },
      payload.length + 5,
    ));
  }

  // --- Single-callback decoder for the Unpacker ---

  Object? _decodeExt(int extType, Uint8List data) {
    final target = _idToExt[extType];
    if (target == null) {
      throw MessagePackConfigurationException(
        'No decoder for extId $extType.',
        '',
      );
    }

    if (target is _Ext) {
      return target.decoder(data, this);
    }

    // It's a group (Map<int, _Ext>), read subId and route.
    final reader = BinaryReader(data);
    final subId = reader.readVarUint();
    final ext = (target as Map<int, _Ext>)[subId];

    if (ext == null) {
      throw MessagePackConfigurationException(
        'Subtype id $subId not found in group $extType.',
        '',
      );
    }

    return ext.decoder(reader.readRemainingBytes(), this);
  }
}

class _MPackEncoder extends Converter<Object?, Uint8List> {
  _MPackEncoder(this._m);
  final MessagePack _m;
  @override
  Uint8List convert(Object? input) => _m.pack(input);
}

class _MPackDecoder extends Converter<Uint8List, Object?> {
  _MPackDecoder(this._m);
  final MessagePack _m;
  @override
  Object? convert(Uint8List input) => _m.unpack(input);
}

/// A builder for grouping multiple types under a single extension ID.
class MessagePackGroup {
  MessagePackGroup(this._m, this._extId) {
    _m._idToExt[_extId] = _subDecoders;
  }

  final MessagePack _m;
  final int _extId;
  final Map<int, _Ext> _subDecoders = HashMap();

  void add<T>({
    required int subId,
    required Encoder<T> encoder,
    required Decoder<T> decoder,
  }) {
    assert(T != dynamic && T != Object, 'Specify a concrete type <T>.');
    if (_subDecoders.containsKey(subId)) {
      throw MessagePackConfigurationException(
        'Subtype id $subId already registered in group $_extId.',
        '',
      );
    }
    final ext = _Ext(
      _extId,
      subId,
      (v, ctx) => encoder(v as T, ctx),
      (d, ctx) => decoder(d, ctx),
    );
    _subDecoders[subId] = ext;
    _m._add(_extId, T, ext);
  }
}

class _Ext {
  _Ext(this.id, this.subId, this.encoder, this.decoder);
  final int id;
  final int? subId;
  final Uint8List Function(Object?, MessagePackContext) encoder;
  final Object? Function(Uint8List, MessagePackContext) decoder;
}

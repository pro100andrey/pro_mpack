/// MessagePack serialization library with extension support.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:pro_binary/pro_binary.dart';

import 'src/deserializer.dart';
import 'src/serializer.dart';

export 'src/deserializer.dart';
export 'src/error.dart';
export 'src/serializer.dart';

Uint8List serialize(
  Object? value, {
  ExtEncoder? extEncoder,
  int initialBufferSize = 1024,
}) {
  final s = Serializer(
    extEncoder: extEncoder,
    initialBufferSize: initialBufferSize,
  )..encode(value);

  return s.takeBytes();
}

Uint8List serializeAll(
  Iterable<Object?> values, {
  ExtEncoder? extEncoder,
  int initialBufferSize = 1024,
}) {
  final s = Serializer(
    extEncoder: extEncoder,
    initialBufferSize: initialBufferSize,
  );

  // Optimize for-loop to avoid closure allocation
  // ignore: prefer_foreach
  for (final value in values) {
    s.encode(value);
  }

  return s.takeBytes();
}

Object? deserialize(
  Uint8List buffer, {
  ExtDecoder? extDecoder,
}) {
  final d = Deserializer(buffer, extDecoder: extDecoder);

  return d.decode();
}

List<Object?> deserializeAll(
  Uint8List buffer, {
  ExtDecoder? extDecoder,
}) {
  final d = Deserializer(buffer, extDecoder: extDecoder);

  final results = <Object?>[];
  while (d.hasBytesAvailable) {
    results.add(d.decode());
  }

  return results;
}

class MessagePackCodec extends Codec<Object?, Uint8List> {
  const MessagePackCodec({
    this.registry,
    this.defaultBufferSize = 1024,
  });

  final MessagePackRegistry? registry;
  final int defaultBufferSize;

  @override
  Converter<Object?, Uint8List> get encoder =>
      _MessagePackEncoder(registry, defaultBufferSize);

  @override
  Converter<Uint8List, Object?> get decoder => _MessagePackDecoder(registry);
}

class _MessagePackEncoder extends Converter<Object?, Uint8List> {
  _MessagePackEncoder(this.registry, this.bufferSize);
  final ExtEncoder? registry;
  final int bufferSize;

  @override
  Uint8List convert(Object? input) {
    final s = Serializer(extEncoder: registry, initialBufferSize: bufferSize)
      ..encode(input);
    return s.takeBytes();
  }
}

class _MessagePackDecoder extends Converter<Uint8List, Object?> {
  _MessagePackDecoder(this.registry);
  final ExtDecoder? registry;

  @override
  Object? convert(Uint8List input) =>
      Deserializer(input, extDecoder: registry).decode();
}

const msgpack = MessagePackCodec();

extension MessagePackObjectX on Object? {
  Uint8List encode({Codec<Object?, Uint8List> codec = msgpack}) =>
      codec.encode(this);
}

extension MessagePackBinaryX on Uint8List {
  T decode<T>({Codec<Object?, Uint8List> codec = msgpack}) =>
      codec.decode(this) as T;
}

/// Base class for codecs that encode values
abstract class MessagePackExtension {
  int get typeId;
  bool canHandle(Object? value);
  Uint8List encode(Object? value, MessagePackRegistry registry);
  Object? decode(Uint8List data, MessagePackRegistry registry);

  static MessagePackExtension create<T>({
    required int typeId,
    required Uint8List Function(T value, MessagePackRegistry registry) encoder,
    required T Function(Uint8List data, MessagePackRegistry registry) decoder,
  }) => _MessagePackExtensionImpl(
    typeId: typeId,
    canHandleFn: (v) => v is T,
    encodeFn: (v, reg) => encoder(v as T, reg),
    decodeFn: (d, reg) => decoder(d, reg),
  );
}

class _MessagePackExtensionImpl implements MessagePackExtension {
  _MessagePackExtensionImpl({
    required this.typeId,
    required bool Function(Object?) canHandleFn,
    required Uint8List Function(Object?, MessagePackRegistry) encodeFn,
    required Object? Function(Uint8List, MessagePackRegistry) decodeFn,
  }) : _canHandleFn = canHandleFn,
       _encodeFn = encodeFn,
       _decodeFn = decodeFn;

  @override
  final int typeId;
  final bool Function(Object?) _canHandleFn;
  final Uint8List Function(Object?, MessagePackRegistry) _encodeFn;
  final Object? Function(Uint8List, MessagePackRegistry) _decodeFn;

  @override
  bool canHandle(Object? value) => _canHandleFn(value);

  @override
  Uint8List encode(Object? value, MessagePackRegistry registry) =>
      _encodeFn(value, registry);

  @override
  Object? decode(Uint8List data, MessagePackRegistry registry) =>
      _decodeFn(data, registry);
}

class MessagePackRegistry implements ExtEncoder, ExtDecoder {
  MessagePackRegistry([List<MessagePackExtension>? initial]) {
    initial?.forEach(register);
  }
  final List<MessagePackExtension> _extensions = [];
  final Map<int, MessagePackExtension> _decoderMap = {};
  final Map<Type, MessagePackExtension?> _typeCache = {};

  MessagePackRegistry register(MessagePackExtension ext) {
    _extensions.add(ext);

    if (_decoderMap.containsKey(ext.typeId)) {
      throw Exception('Extension with typeId ${ext.typeId} already registered');
    }

    _decoderMap[ext.typeId] = ext;
    _typeCache.clear();
    // Allow method chaining
    // ignore: avoid_returning_this
    return this;
  }

  MessagePackRegistry registerSub(int typeId, MessagePackSubRegistry sub) =>
      register(sub.toExtension(typeId));

  /// Packs multiple objects into a MessagePack-encoded `Uint8List`.
  Uint8List packAll(List<Object?> values) =>
      serializeAll(values, extEncoder: this);

  /// Unpacks multiple MessagePack-encoded objects from [data].
  List<Object?> unpackAll(Uint8List data) =>
      deserializeAll(data, extDecoder: this);

  /// Packs a single object into a MessagePack-encoded `Uint8List`.
  Uint8List pack<T>(T? value) => serialize(value, extEncoder: this);

  /// Unpacks a single MessagePack-encoded object from [data].
  T? unpack<T>(Uint8List data) => deserialize(data, extDecoder: this) as T?;

  @override
  int? extTypeForObject(Object? object) {
    if (object == null) {
      return null;
    }

    final type = object.runtimeType;

    final ext = _typeCache[type];
    if (ext != null) {
      return ext.typeId;
    }

    for (var i = 0; i < _extensions.length; i++) {
      final e = _extensions[i];

      if (e.canHandle(object)) {
        _typeCache[type] = e;
        return e.typeId;
      }
    }

    return null;
  }

  @override
  Uint8List encodeObject(Object? object) {
    final typeId = extTypeForObject(object);
    if (typeId == null) {
      throw Exception('No encoder for ${object.runtimeType}');
    }
    return _decoderMap[typeId]!.encode(object, this);
  }

  @override
  Object? decodeObject(int extType, Uint8List data) {
    final ext = _decoderMap[extType];
    if (ext == null) {
      throw Exception('No decoder for extension $extType');
    }
    return ext.decode(data, this);
  }
}

typedef _DecoderMap =
    Map<int, Object? Function(Uint8List, MessagePackRegistry)>;
typedef _EncoderMap =
    Map<int, Uint8List Function(Object?, MessagePackRegistry)>;

class MessagePackSubRegistry<Base> {
  final Map<Type, int> _typeToId = {};

  final _DecoderMap _decoders = {};
  final _EncoderMap _encoders = {};

  MessagePackSubRegistry<Base> add<T>({
    required int subId,
    required Uint8List Function(T value, MessagePackRegistry reg) encoder,
    required T Function(Uint8List data, MessagePackRegistry reg) decoder,
  }) {
    _typeToId[T] = subId;
    _encoders[subId] = (v, reg) => encoder(v as T, reg);
    _decoders[subId] = (d, reg) => decoder(d, reg);
    // Allow method chaining
    // ignore: avoid_returning_this
    return this;
  }

  MessagePackExtension toExtension(int mainTypeId) =>
      MessagePackExtension.create<Base>(
        typeId: mainTypeId,
        encoder: (value, registry) {
          final subId = _typeToId[value.runtimeType];
          if (subId == null) {
            throw Exception('Subtype ${value.runtimeType} not registered');
          }

          final payload = _encoders[subId]!(value, registry);
          final writer = BinaryWriter(initialBufferSize: payload.length + 4)
            ..writeVarInt(subId)
            ..writeBytes(payload);

          return writer.takeBytes();
        },
        decoder: (data, registry) {
          final reader = BinaryReader(data);
          final subId = reader.readVarInt();
          final payload = reader.readRemainingBytes();

          final decoderFn = _decoders[subId];
          if (decoderFn == null) {
            throw Exception('Unknown subTypeId: $subId');
          }

          return decoderFn(payload, registry) as Base;
        },
      );
}

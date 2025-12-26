/// A high-performance Dart library for serializing and deserializing
/// objects to and from MessagePack.
///
/// MessagePack is an efficient binary serialization format that provides
/// a compact representation for data interchange. This library offers:
///
/// - Fast serialization and deserialization of Dart objects
/// - Support for all MessagePack types (nil, boolean, integer, float,
///   string, binary, array, map, extension)
/// - Custom extension type encoding/decoding
/// - Built-in DateTime timestamp support
/// - Optimized performance with configurable buffer sizes
/// - Zero-copy operations where possible
///
/// ## Basic Usage
///
/// ```dart
/// import 'package:pro_mpack/pro_mpack.dart';
/// // Serialize data
/// final bytes = serialize({'name': 'John', 'age': 30});
/// // Deserialize data
/// final data = deserialize(bytes);
/// print(data); // {name: John, age: 30}
/// ```
///
/// ## Custom Extension Types
///
/// For custom types, implement [ExtEncoder] and [ExtDecoder]:
///
/// ```dart
/// class MyEncoder with ExtEncoder {
///   @override
///   int? extTypeForObject(Object? object) => object is MyClass ? 42 : null;
///   @override
///   Uint8List encodeObject(Object? object) => ...
/// }
/// ```
/// See the README for complete examples and documentation.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:pro_binary/pro_binary.dart';

import 'pro_mpack.dart' show MessagePackError;
import 'src/deserializer.dart';
import 'src/error.dart' show MessagePackError;
import 'src/serializer.dart';

export 'src/deserializer.dart';
export 'src/error.dart';
export 'src/serializer.dart';

/// Serializes an object to a MessagePack-encoded `Uint8List`.
///
/// This function converts a Dart object into a binary format using MessagePack
/// encoding. The supported types include null, boolean, integers, strings,
/// lists, maps, and custom extension types.
///
/// Example:
/// ```dart
/// final data = serialize({'key': 'value'});
/// ```
///
/// [value]: The Dart object to be serialized. It can be of any supported type.
/// [extEncoder]: An optional custom encoder function for handling extension
/// types. If not provided, no custom extensions will be encoded.
/// [initialBufferSize]: The initial size of the buffer used for encoding. This
/// value is used to optimize the encoding process by reducing the number of
/// reallocations. Defaults to `1024`.
///
/// Returns a `Uint8List` containing the MessagePack-encoded binary data.
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

/// Serializes multiple objects sequentially to a MessagePack-encoded
/// `Uint8List`.
///
/// This function is useful when you need to serialize a stream of objects
/// into a single buffer without array wrapping. Each object is encoded one
/// after another.
///
/// Example:
/// ```dart
/// final data = serializeAll([123, 'hello', {'key': 'value'}]);
/// // The buffer contains three consecutive MessagePack-encoded values
/// ```
///
/// This differs from `serialize([...])` which wraps values in a
/// MessagePack array. Use `serializeAll` when you want to encode multiple
/// independent messages in one buffer.
///
/// [values]: An iterable of Dart objects to be serialized sequentially.
/// [extEncoder]: An optional custom encoder function for handling
/// extension types. If not provided, custom extensions will not be encoded.
/// [initialBufferSize]: The initial size of the buffer used for encoding.
/// Defaults to `1024`. Larger buffers may improve performance when
/// encoding many or large objects.
///
/// Returns a `Uint8List` containing all MessagePack-encoded values
/// concatenated.
///
/// See also:
/// * [deserializeAll] for deserializing multiple consecutive values.
Uint8List serializeAll(
  Iterable<Object?> values, {
  ExtEncoder? extEncoder,
  int initialBufferSize = 1024,
}) {
  final s = Serializer(
    extEncoder: extEncoder,
    initialBufferSize: initialBufferSize,
  );

  // Optimize for List<Object?> to avoid dynamic calls.
  if (values is List<Object?>) {
    for (var i = 0; i < values.length; i++) {
      s.encode(values[i]);
    }
  } else {
    //
    // ignore: prefer_foreach
    for (final value in values) {
      s.encode(value);
    }
  }

  return s.takeBytes();
}

/// Deserializes a MessagePack-encoded `Uint8List` into a Dart object.
///
/// This function converts binary MessagePack data back into Dart objects.
/// Supported types include:
/// - `null` (nil)
/// - `bool` (true/false)
/// - `int` (signed/unsigned integers up to 64-bit)
/// - `double` (32-bit and 64-bit floating point)
/// - `String` (UTF-8 encoded)
/// - `Uint8List` (binary data)
/// - `List` (arrays)
/// - `Map` (maps with any key/value types)
/// - `DateTime` (timestamp extension type)
/// - Custom extension types (via [ExtDecoder])
///
/// Example:
/// ```dart
/// final bytes = serialize({'name': 'Alice', 'score': 95});
/// final obj = deserialize(bytes);
/// print(obj['name']); // Alice
/// ```
///
/// With custom extension decoder:
/// ```dart
/// final obj = deserialize(bytes, extDecoder: MyDecoder());
/// ```
///
/// [list]: The `Uint8List` containing the MessagePack-encoded binary
/// data.
/// [extDecoder]: An optional custom decoder for handling extension types.
///
/// Returns the deserialized Dart object, which can be `null`, a primitive
/// type, a collection (`List` or `Map`), or a custom type decoded by
/// [extDecoder].
///
/// Throws [MessagePackError] if the data is not valid MessagePack format.
Object? deserialize(
  Uint8List list, {
  ExtDecoder? extDecoder,
}) {
  final d = Deserializer(list, extDecoder: extDecoder);

  return d.decode();
}

/// Deserializes multiple consecutive MessagePack-encoded values from a
/// `Uint8List`.
///
/// This function reads and deserializes all available MessagePack values
/// from the buffer sequentially. It's the counterpart to [serializeAll] and
/// is useful when processing a stream of MessagePack messages or multiple
/// independent values encoded consecutively.
///
/// Example:
/// ```dart
/// final bytes = serializeAll([42, 'hello', true]);
/// final objects = deserializeAll(bytes);
/// print(objects); // [42, hello, true]
/// ```
///
/// This differs from deserializing a single array, as each value is a
/// separate MessagePack message rather than elements of a single array
/// message.
///
/// [list]: The `Uint8List` containing multiple MessagePack-encoded
/// values.
/// [extDecoder]: An optional custom decoder for handling extension types.
///
/// Returns a `List` containing all deserialized objects in the order they
/// appear.
///
/// Throws [MessagePackError] if any value in the buffer is not valid
/// MessagePack format.
///
/// See also:
/// * [serializeAll] for serializing multiple values consecutively.
List<Object?> deserializeAll(
  Uint8List list, {
  ExtDecoder? extDecoder,
}) {
  final d = Deserializer(list, extDecoder: extDecoder);

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
  final MsgPackRegistry? registry;
  final int defaultBufferSize;

  @override
  Converter<Object?, Uint8List> get encoder =>
      _MsgPackEncoder(registry, defaultBufferSize);

  @override
  Converter<Uint8List, Object?> get decoder => _MsgPackDecoder(registry);
}

class _MsgPackEncoder extends Converter<Object?, Uint8List> {
  _MsgPackEncoder(this.registry, this.bufferSize);
  final ExtEncoder? registry;
  final int bufferSize;

  @override
  Uint8List convert(Object? input) {
    final s = Serializer(extEncoder: registry, initialBufferSize: bufferSize)
      ..encode(input);
    return s.takeBytes();
  }
}

class _MsgPackDecoder extends Converter<Uint8List, Object?> {
  _MsgPackDecoder(this.registry);
  final ExtDecoder? registry;

  @override
  Object? convert(Uint8List input) =>
      Deserializer(input, extDecoder: registry).decode();
}

const msgpack = MessagePackCodec();

extension MsgPackObjectX on Object? {
  Uint8List toMsgPack({MessagePackCodec codec = msgpack}) => codec.encode(this);
}

extension MsgPackBinaryX on Uint8List {
  T fromMsgPack<T>({MessagePackCodec codec = msgpack}) =>
      codec.decode(this) as T;
}

abstract class MsgPackExtension {
  int get typeId;
  bool canHandle(Object? value);
  Uint8List encode(Object? value);
  Object? decode(Uint8List data);

  static MsgPackExtension create<T>({
    required int typeId,
    required Uint8List Function(T value) encoder,
    required T Function(Uint8List data) decoder,
  }) => _MsgPackExtensionImpl(
    typeId: typeId,
    canHandleFn: (value) => value is T,
    encodeFn: (value) => encoder(value as T),
    decodeFn: (data) => decoder(data),
  );
}

class _MsgPackExtensionImpl implements MsgPackExtension {
  _MsgPackExtensionImpl({
    required this.typeId,
    required bool Function(Object?) canHandleFn,
    required Uint8List Function(Object?) encodeFn,
    required Object? Function(Uint8List) decodeFn,
  }) : _canHandleFn = canHandleFn,
       _encodeFn = encodeFn,
       _decodeFn = decodeFn;
  @override
  final int typeId;
  final bool Function(Object?) _canHandleFn;
  final Uint8List Function(Object?) _encodeFn;
  final Object? Function(Uint8List) _decodeFn;

  @override
  bool canHandle(Object? value) => _canHandleFn(value);

  @override
  Uint8List encode(Object? value) => _encodeFn(value);

  @override
  Object? decode(Uint8List data) => _decodeFn(data);
}

class MsgPackRegistry implements ExtEncoder, ExtDecoder {
  MsgPackRegistry(this._extensions)
    : _decoderMap = {for (final e in _extensions) e.typeId: e};
  final List<MsgPackExtension> _extensions;
  final Map<int, MsgPackExtension> _decoderMap;

  @override
  int? extTypeForObject(Object? object) {
    for (final ext in _extensions) {
      if (ext.canHandle(object)) {
        return ext.typeId;
      }
    }

    return null;
  }

  @override
  Uint8List encodeObject(Object? object) {
    for (final ext in _extensions) {
      if (ext.canHandle(object)) {
        return ext.encode(object);
      }
    }

    throw MessagePackError('No encoder found for ${object.runtimeType}');
  }

  @override
  Object? decodeObject(int extType, Uint8List data) {
    final ext = _decoderMap[extType];
    if (ext == null) {
      throw MessagePackError('No decoder found for extension type $extType');
    }

    return ext.decode(data);
  }
}

class MsgPackSubRegistry<Base> {
  final Map<Type, int> _typeToId = {};
  final Map<int, Object? Function(Uint8List)> _decoders = {};
  final Map<int, Uint8List Function(Object?)> _encoders = {};

  void register<T>({
    required int subId,
    required Uint8List Function(T) encoder,
    required T Function(Uint8List) decoder,
  }) {
    _typeToId[T] = subId;
    _encoders[subId] = (value) => encoder(value as T);
    _decoders[subId] = (data) => decoder(data);
  }

  MsgPackExtension asExtension(int mainTypeId) => MsgPackExtension.create<Base>(
    typeId: mainTypeId,
    encoder: (value) {
      final subId = _typeToId[value.runtimeType];
      if (subId == null) {
        throw Exception('Subtype ${value.runtimeType} not registered');
      }

      final payload = _encoders[subId]!(value);

      final writer = BinaryWriter(initialBufferSize: 4 + payload.length)
        ..writeVarInt(subId)
        ..writeBytes(payload);

      return writer.takeBytes();
    },
    decoder: (data) {
      if (data.length < 4) {
        throw Exception('Invalid data for sub-registry: too short');
      }

      final reader = BinaryReader(data);
      final subId = reader.readVarInt();
      final payload = reader.readRemainingBytes();

      final decoder = _decoders[subId];
      if (decoder == null) {
        throw Exception('Unknown subTypeId: $subId');
      }

      return decoder(payload) as Base;
    },
  );
}

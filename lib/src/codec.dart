import 'dart:convert';
import 'dart:typed_data';

import 'deserializer.dart';
import 'registry.dart';
import 'serializer.dart';

/// A codec for encoding and decoding MessagePack data.
///
/// This codec provides a high-level interface for MessagePack serialization,
/// integrating with Dart's `dart:convert` library. It can be used with
/// streams, converters, and other standard Dart conversion APIs.
///
/// The codec supports optional extension types through a [MessagePackRegistry],
/// allowing you to encode and decode custom types beyond the standard
/// MessagePack types.
///
/// Example:
/// ```dart
/// // Using the default codec
/// const codec = MessagePackCodec();
/// final encoded = codec.encode({'key': 'value'});
/// final decoded = codec.decode(encoded);
/// // Using a codec with a custom registry
/// final registry = MessagePackRegistry()..register(myExtension);
/// final customCodec = MessagePackCodec(registry: registry);
/// final data = customCodec.encode(myCustomObject);
/// ```
///
/// See also:
/// - [msgpack], a convenient constant instance of this codec
/// - [MessagePackRegistry], for registering custom extension types
class MessagePackCodec extends Codec<Object?, Uint8List> {
  /// Creates a new MessagePack codec.
  ///
  /// The [registry] parameter allows you to specify a custom registry for
  /// handling extension types. If not provided, only standard MessagePack
  /// types will be supported.
  ///
  /// The [defaultBufferSize] parameter controls the initial buffer size
  /// used by the encoder. The buffer will grow automatically if needed.
  /// The default value of 1024 bytes is suitable for most use cases.
  const MessagePackCodec({
    this.registry,
    this.defaultBufferSize = 1024,
  });

  /// The registry used for encoding and decoding extension types.
  ///
  /// If `null`, only standard MessagePack types are supported.
  final MessagePackRegistry? registry;

  /// The initial buffer size for the encoder.
  ///
  /// This value is used to allocate the initial encoding buffer. The buffer
  /// will grow automatically if more space is needed. Larger values reduce
  /// the need for buffer resizing but use more memory upfront.
  final int defaultBufferSize;

  /// Returns a converter that encodes objects to MessagePack format.
  @override
  Converter<Object?, Uint8List> get encoder =>
      _MessagePackEncoder(registry, defaultBufferSize);

  /// Returns a converter that decodes MessagePack data to objects.
  @override
  Converter<Uint8List, Object?> get decoder => _MessagePackDecoder(registry);
}

/// Internal encoder implementation for MessagePack codec.
///
/// This converter transforms Dart objects into MessagePack-encoded byte arrays.
/// It uses a [Serializer] internally to handle the actual encoding process.
class _MessagePackEncoder extends Converter<Object?, Uint8List> {
  _MessagePackEncoder(this.registry, this.bufferSize);

  /// Optional extension encoder for custom types.
  final ExtEncoder? registry;

  /// Initial buffer size for the serializer.
  final int bufferSize;

  /// Converts [input] to a MessagePack-encoded [Uint8List].
  ///
  /// Supports all standard MessagePack types:
  /// - null
  /// - bool
  /// - int (including negative integers)
  /// - double
  /// - String (UTF-8 encoded)
  /// - Uint8List (binary data)
  /// - List (arrays)
  /// - Map (objects)
  ///
  /// Extension types are supported if a registry is provided.
  @override
  Uint8List convert(Object? input) {
    final s = Serializer(extEncoder: registry, initialBufferSize: bufferSize)
      ..encode(input);
    return s.takeBytes();
  }
}

/// Internal decoder implementation for MessagePack codec.
///
/// This converter transforms MessagePack-encoded byte arrays back into
/// Dart objects. It uses a [Deserializer] internally to handle the actual
/// decoding process.
class _MessagePackDecoder extends Converter<Uint8List, Object?> {
  _MessagePackDecoder(this.registry);

  /// Optional extension decoder for custom types.
  final ExtDecoder? registry;

  /// Converts a MessagePack-encoded [input] buffer to a Dart object.
  ///
  /// Returns the decoded value, which can be any of the standard MessagePack
  /// types or a custom extension type if a registry is provided.
  ///
  /// Throws an exception if the data is malformed or if an unknown extension
  /// type is encountered without a corresponding decoder.
  @override
  Object? convert(Uint8List input) =>
      Deserializer(input, extDecoder: registry).decode();
}

/// Default MessagePack codec instance.
///
/// A pre-configured codec that can be used for basic MessagePack encoding
/// and decoding without extension types. This is the most convenient way
/// to use MessagePack for standard types.
///
/// Example:
/// ```dart
/// // Encoding
/// final data = msgpack.encode({'name': 'Alice', 'age': 30});
/// // Decoding
/// final decoded = msgpack.decode(data);
/// print(decoded); // {name: Alice, age: 30}
/// // Using with extension methods
/// final encoded = {'key': 'value'}.encode();
/// final decoded = encoded.decode<Map>();
/// ```
///
/// For custom types, create a [MessagePackCodec] with a [MessagePackRegistry].
const msgpack = MessagePackCodec();

/// Extension methods for encoding objects to MessagePack format.
///
/// Provides convenient encoding methods on any Dart object, allowing you
/// to call `.encode()` directly on values.
///
/// Example:
/// ```dart
/// // Encode various types
/// final stringData = 'hello'.encode();
/// final intData = 42.encode();
/// final mapData = {'key': 'value'}.encode();
/// final listData = [1, 2, 3].encode();
///
/// // Using a custom codec
/// final customCodec = MessagePackCodec(registry: myRegistry);
/// final data = myObject.encode(codec: customCodec);
/// ```
extension MessagePackObjectX on Object? {
  /// Encodes this object to MessagePack format.
  ///
  /// The [codec] parameter allows you to specify a custom codec. If not
  /// provided, the default [msgpack] codec is used.
  ///
  /// Returns a [Uint8List] containing the encoded data.
  Uint8List encode({Codec<Object?, Uint8List> codec = msgpack}) =>
      codec.encode(this);
}

/// Extension methods for decoding MessagePack data.
///
/// Provides convenient decoding methods on [Uint8List] byte arrays,
/// allowing you to call `.decode()` directly on encoded data.
///
/// Example:
/// ```dart
/// // Decode to a specific type
/// final data = someBytes.decode<Map<String, dynamic>>();
/// // Decode without type parameter
/// final value = someBytes.decode();
/// // Using a custom codec
/// final customCodec = MessagePackCodec(registry: myRegistry);
/// final object = someBytes.decode<MyClass>(codec: customCodec);
/// ```
extension MessagePackBinaryX on Uint8List {
  /// Decodes this byte array from MessagePack format.
  ///
  /// The type parameter [T] allows you to specify the expected return type
  /// for better type safety. The decoded value is cast to [T].
  ///
  /// The [codec] parameter allows you to specify a custom codec. If not
  /// provided, the default [msgpack] codec is used.
  ///
  /// Returns the decoded object of type [T].
  ///
  /// Throws an exception if the data is malformed or cannot be decoded.
  T decode<T>({Codec<Object?, Uint8List> codec = msgpack}) =>
      codec.decode(this) as T;
}

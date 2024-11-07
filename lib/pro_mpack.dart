/// A library for serializing and deserializing objects to and from MessagePack.
library;

import 'dart:typed_data';

import 'src/deserializer.dart';
import 'src/serializer.dart';

export 'src/deserializer.dart';
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
/// reallocations. Defaults to `64`.
///
/// Returns a `Uint8List` containing the MessagePack-encoded binary data.
Uint8List serialize(
  Object? value, {
  ExtEncoder? extEncoder,
  int initialBufferSize = 64,
}) {
  final s =
      Serializer(extEncoder: extEncoder, initialBufferSize: initialBufferSize)
        ..encode(value);

  return s.takeBytes();
}

/// Deserializes a MessagePack-encoded `Uint8List` into a Dart object.
///
/// This function converts a binary format using MessagePack encoding back into
/// a Dart object. The supported types include null, boolean, integers, strings,
/// lists, maps, and custom extension types.
///
/// Example:
/// ```dart
/// final obj = deserialize(data);
/// ```
///
/// [list]: The `Uint8List` containing the MessagePack-encoded binary data.
/// [extDecoder]: An optional custom decoder function for handling extension
/// types. If not provided, no custom extensions will be decoded.
/// [copyBinaryData]: A flag indicating whether to copy binary data. This is
/// useful when you want to ensure the original data is not modified. Defaults
/// to `false`.
///
/// Returns the deserialized Dart object, which can be of any supported type.
Object? deserialize(
  Uint8List list, {
  ExtDecoder? extDecoder,
  bool copyBinaryData = false,
}) {
  final d = Deserializer(
    list,
    extDecoder,
  );

  return d.decode();
}

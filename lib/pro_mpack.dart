/// @docImport 'src/message_pack.dart';
/// A high-performance MessagePack serialization and deserialization library
/// with full extension support.
///
/// This library provides a high-level API for encoding and decoding
/// MessagePack data, as well as access to the underlying [Packer]
/// and [Unpacker] for more granular control.
///
/// For most use cases, the [serialize] and [deserialize] functions are
/// sufficient. For advanced scenarios requiring custom extension registration
/// with high-performance caching (O(1) lookups), use the [MessagePack] class.
library;

import 'dart:typed_data' show Uint8List;

import 'src/core/exception.dart';
import 'src/core/packer.dart';
import 'src/core/unpacker.dart';

export 'src/core/exception.dart';
export 'src/core/packer.dart' show EncodeExt, Float, Packer;
export 'src/core/unpacker.dart' show DecodeExt, Unpacker;
export 'src/message_pack.dart'
    show Decoder, Encoder, MessagePack, MessagePackGroup;
export 'src/stream/transformer.dart' show MessagePackStreamTransformer;

/// Serializes [value] into the MessagePack binary format.
///
/// The resulting [Uint8List] contains the encoded representation of the
/// provided object.
///
/// Supported types include:
/// - `null`, `bool`, `int`, `double`
/// - `String` (UTF-8 encoded)
/// - `Uint8List`, `ByteData` (binary data)
/// - `List`, `Map`, `Iterable` (collections)
/// - `DateTime` (using the MessagePack timestamp extension)
/// - [Float] (for explicit 32-bit floating point numbers)
///
/// [encodeExt] can be provided to handle custom extension types.
/// [initialBufferSize] determines the starting capacity of the internal
/// encoder buffer (default is 1024 bytes).
///
/// Throws a [MessagePackException] if serialization fails.
///
/// **Note:** For repetitive serialization of similar custom types, consider
/// using the [MessagePack] class which implements advanced caching for faster
/// lookups.
@pragma('vm:prefer-inline')
Uint8List serialize(
  Object? value, {
  EncodeExt? encodeExt,
  int initialBufferSize = 1024,
}) {
  final packer = Packer(
    encodeExt: encodeExt,
    initialBufferSize: initialBufferSize,
  );

  try {
    packer.pack(value);
    return packer.takeBytes();
  } finally {
    packer.dispose();
  }
}

/// Serializes a sequence of [values] into a single MessagePack buffer.
///
/// This is useful for streaming or protocol-level implementations where
/// multiple MessagePack objects are concatenated without a top-level array.
///
/// [encodeExt] and [initialBufferSize] behave the same as in [serialize].
///
/// Throws a [MessagePackException] if any value fails to serialize.
@pragma('vm:prefer-inline')
Uint8List serializeAll(
  Iterable<dynamic> values, {
  EncodeExt? encodeExt,
  int initialBufferSize = 1024,
}) {
  final packer = Packer(
    encodeExt: encodeExt,
    initialBufferSize: initialBufferSize,
  );

  try {
    for (final value in values) {
      packer.pack(value);
    }
    return packer.takeBytes();
  } finally {
    packer.dispose();
  }
}

/// Deserializes a single value from a MessagePack [buffer].
///
/// The function reads the first complete MessagePack object from the buffer.
///
/// [decodeExt] can be provided to handle custom extension types.
///
/// Throws a [MessagePackException] if the buffer contains invalid MessagePack
/// data or is empty.
/// Throws a [RangeError] if the buffer is exhausted prematurely mid-value.
@pragma('vm:prefer-inline')
dynamic deserialize(Uint8List buffer, {DecodeExt? decodeExt}) {
  final unpacker = Unpacker(buffer: buffer, decodeExt: decodeExt);
  final result = unpacker.unpack();

  return result;
}

/// Deserializes all MessagePack objects from the provided [buffer] into a list.
///
/// Useful for decoding buffers created with [serializeAll] or streams of
/// MessagePack data.
///
/// Throws a [MessagePackException] if any part of the buffer contains invalid
/// MessagePack data.
/// Throws a [RangeError] if the buffer is exhausted prematurely mid-value.
@pragma('vm:prefer-inline')
List<dynamic> deserializeAll(Uint8List buffer, {DecodeExt? decodeExt}) {
  final unpacker = Unpacker(buffer: buffer, decodeExt: decodeExt);
  final result = <dynamic>[];

  while (unpacker.hasBytesAvailable) {
    result.add(unpacker.unpack());
  }

  return result;
}

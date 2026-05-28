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
export 'src/core/packer.dart' show EncodeExt, ExtEncoded, Float, Packer;
export 'src/core/unpacker.dart' show DecodeExt, Unpacker;
export 'src/message_pack.dart'
    show MessagePack, MessagePackCtx, MessagePackGroup;

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
/// **Note:** For repetitive serialization of similar custom types, consider using
/// the [MessagePack] class which implements advanced caching for faster lookups.
Uint8List serialize(
  Object? value, {
  EncodeExt? encodeExt,
  int initialBufferSize = 1024,
}) {
  final s = Packer(
    encodeExt: encodeExt,
    initialBufferSize: initialBufferSize,
  );

  try {
    s.pack(value);
    return s.takeBytes();
  } finally {
    s.dispose();
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
Uint8List serializeAll(
  Iterable<Object?> values, {
  EncodeExt? encodeExt,
  int initialBufferSize = 1024,
}) {
  final s = Packer(
    encodeExt: encodeExt,
    initialBufferSize: initialBufferSize,
  );

  try {
    s.packAll(values);
    return s.takeBytes();
  } finally {
    s.dispose();
  }
}

/// Deserializes a single value from a MessagePack [buffer].
///
/// The function reads the first complete MessagePack object from the buffer.
///
/// [decodeExt] can be provided to handle custom extension types.
/// [preserveMapOrder] if true, uses a [LinkedHashMap] (default Dart Map) to
/// maintain key order; if false, may use a more performant [HashMap].
///
/// Throws a [MessagePackException] if the buffer contains invalid MessagePack
/// data or if the buffer is exhausted prematurely.
Object? deserialize(
  Uint8List buffer, {
  DecodeExt? decodeExt,
  bool preserveMapOrder = false,
}) {
  final d = Unpacker(
    buffer: buffer,
    decodeExt: decodeExt,
    preserveMapOrder: preserveMapOrder,
  );

  final result = d.unpack();

  return result;
}

/// Deserializes all MessagePack objects from the provided [buffer] into a list.
///
/// Useful for decoding buffers created with [serializeAll] or streams of
/// MessagePack data.
///
/// [decodeExt] and [preserveMapOrder] behave the same as in [deserialize].
///
/// Throws a [MessagePackException] if any part of the buffer contains invalid
/// MessagePack data.
List<Object?> deserializeAll(
  Uint8List buffer, {
  DecodeExt? decodeExt,
  bool preserveMapOrder = false,
}) {
  final d = Unpacker(
    buffer: buffer,
    decodeExt: decodeExt,
    preserveMapOrder: preserveMapOrder,
  );

  final results = <Object?>[];
  while (d.hasBytesAvailable) {
    final value = d.unpack();
    results.add(value);
  }

  return results;
}

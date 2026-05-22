/// A high-performance MessagePack serialization and deserialization library
/// with full extension support.
///
/// This library provides a high-level API for encoding and decoding
/// MessagePack data, as well as access to the underlying [Serializer]
/// and [Deserializer] for more granular control.
///
/// For most use cases, the [serialize] and [deserialize] functions are
/// sufficient. For custom types, use [ExtEncoder] and [ExtDecoder].
library;

import 'dart:collection';
import 'dart:typed_data';

import 'src/core/deserializer.dart';
import 'src/core/error.dart';
import 'src/core/serializer.dart';

export 'src/core/deserializer.dart';
export 'src/core/error.dart';
export 'src/core/serializer.dart';
export 'src/message_pack.dart';

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
/// [extEncoder] can be provided to handle custom extension types.
/// [initialBufferSize] determines the starting capacity of the internal
/// encoder buffer (default is 1024 bytes).
///
/// Throws a [MessagePackError] if serialization fails.
Uint8List serialize(
  Object? value, {
  ExtEncoder? extEncoder,
  int initialBufferSize = 1024,
}) {
  final s = Serializer(
    extEncoder: extEncoder,
    initialBufferSize: initialBufferSize,
  )..encode(value);

  final result = s.takeBytes();

  return result;
}

/// Serializes a sequence of [values] into a single MessagePack buffer.
///
/// This is useful for streaming or protocol-level implementations where
/// multiple MessagePack objects are concatenated without a top-level array.
///
/// [extEncoder] and [initialBufferSize] behave the same as in [serialize].
///
/// Throws a [MessagePackError] if any value fails to serialize.
Uint8List serializeAll(
  Iterable<Object?> values, {
  ExtEncoder? extEncoder,
  int initialBufferSize = 1024,
}) {
  final s = Serializer(
    extEncoder: extEncoder,
    initialBufferSize: initialBufferSize,
  );

  for (final value in values) {
    s.encode(value);
  }

  final result = s.takeBytes();

  return result;
}

/// Deserializes a single value from a MessagePack [buffer].
///
/// The function reads the first complete MessagePack object from the buffer.
///
/// [extDecoder] can be provided to handle custom extension types.
/// [preserveMapOrder] if true, uses a [LinkedHashMap] (default Dart Map) to
/// maintain key order; if false, may use a more performant [HashMap].
///
/// Throws a [MessagePackError] if the buffer contains invalid MessagePack
/// data or if the buffer is exhausted prematurely.
Object? deserialize(
  Uint8List buffer, {
  ExtDecoder? extDecoder,
  bool? preserveMapOrder,
}) {
  final d = Deserializer(
    buffer,
    extDecoder: extDecoder,
    preserveMapOrder: preserveMapOrder,
  );

  final result = d.decode();

  return result;
}

/// Deserializes all MessagePack objects from the provided [buffer] into a list.
///
/// Useful for decoding buffers created with [serializeAll] or streams of
/// MessagePack data.
///
/// [extDecoder] and [preserveMapOrder] behave the same as in [deserialize].
///
/// Throws a [MessagePackError] if any part of the buffer contains invalid
/// MessagePack data.
List<Object?> deserializeAll(
  Uint8List buffer, {
  ExtDecoder? extDecoder,
  bool? preserveMapOrder,
}) {
  final d = Deserializer(
    buffer,
    extDecoder: extDecoder,
    preserveMapOrder: preserveMapOrder,
  );

  final results = <Object?>[];
  while (d.hasBytesAvailable) {
    final value = d.decode();
    results.add(value);
  }

  return results;
}

/// MessagePack serialization library with extension support.
library;

import 'dart:typed_data';

import 'src/core/deserializer.dart';
import 'src/core/serializer.dart';

export 'src/core/deserializer.dart';
export 'src/core/error.dart';
export 'src/core/serializer.dart';
export 'src/message_pack.dart';

/// Serializes [value] to MessagePack format.
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

/// Serializes multiple [values] consecutively.
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

  return s.takeBytes();
}

/// Deserializes a single value from MessagePack [buffer].
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

  return d.decode();
}

/// Deserializes all values from MessagePack [buffer].
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
    results.add(d.decode());
  }

  return results;
}

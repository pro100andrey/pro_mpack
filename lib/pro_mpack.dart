/// MessagePack serialization library with extension support.
library;

import 'dart:typed_data';

import 'src/deserializer.dart';
import 'src/message_pack.dart';
import 'src/serializer.dart';

export 'src/deserializer.dart';
export 'src/error.dart';
export 'src/message_pack.dart';
export 'src/serializer.dart';

/// Default MessagePack instance for quick access.
final msgpack = MessagePack();

/// Serializes [value] to MessagePack format.
Uint8List serialize(
  Object? value, {
  ExtEncoder? extEncoder,
  int initialBufferSize = 1024,
}) {
  if (extEncoder == null) {
    return msgpack.pack(value);
  }
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
  if (extEncoder == null) {
    return msgpack.packAll(values);
  }
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
  if (extDecoder == null && (preserveMapOrder == null || !preserveMapOrder)) {
    return msgpack.unpack(buffer);
  }
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
  if (extDecoder == null && (preserveMapOrder == null || !preserveMapOrder)) {
    return msgpack.unpackAll(buffer);
  }
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

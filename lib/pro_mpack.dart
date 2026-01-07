/// MessagePack serialization library with extension support.
library;

import 'dart:typed_data';

import 'src/deserializer.dart';
import 'src/serializer.dart';

export 'src/codec.dart';
export 'src/deserializer.dart';
export 'src/error.dart';
export 'src/extension.dart';
export 'src/registry.dart';
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

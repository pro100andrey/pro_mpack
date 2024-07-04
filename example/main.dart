import 'dart:typed_data';

import 'package:pro_binary/pro_binary.dart';
import 'package:pro_mpack/pro_mpack.dart';

enum TimeStampFormat {
  ts32,
  ts64,
  ts96;

  static TimeStampFormat fromLength(int length) {
    switch (length) {
      case 4:
        return ts32;
      case 8:
        return ts64;
      case 12:
        return ts96;
      default:
        throw Exception('Invalid timestamp length');
    }
  }
}

/// Custom extension encoder for serializing DateTime objects.
class CustomTypesExtEncoder with ExtEncoder {
  CustomTypesExtEncoder({required this.timeStampFormat});

  /// The format of the timestamp.
  final TimeStampFormat timeStampFormat;

  @override
  int? extTypeForObject(Object? object) {
    if (object is DateTime) {
      return -1;
    }

    throw Exception('Unknown object type');
  }

  @override
  Uint8List encodeObject(Object? object) {
    if (object is DateTime) {
      final writer = BinaryWriter();

      switch (timeStampFormat) {
        case TimeStampFormat.ts32:
          final seconds = object.millisecondsSinceEpoch ~/ 1000;
          writer.writeUint32(seconds);
        case TimeStampFormat.ts64:
          final seconds = object.millisecondsSinceEpoch ~/ 1000;
          final nanoSeconds = (object.microsecondsSinceEpoch % 1000000) * 1000;
          writer.writeUint32(nanoSeconds);
          writer.writeUint32(seconds);
        case TimeStampFormat.ts96:
          final seconds = object.millisecondsSinceEpoch ~/ 1000;
          final nanoSeconds = (object.microsecondsSinceEpoch % 1000000) * 1000;
          writer.writeUint32(nanoSeconds);
          writer.writeInt64(seconds);
      }

      return writer.takeBytes();
    }

    throw Exception('Unknown object type');
  }
}

/// Custom extension decoder for deserializing DateTime objects.
class CustomTypesExtDecoder implements ExtDecoder {
  @override
  Object? decodeObject(int extType, Uint8List data) {
    if (extType == -1) {
      final type = TimeStampFormat.fromLength(data.length);
      final reader = BinaryReader(data);
      switch (type) {
        // Timestamp 32: stores the number of seconds that have elapsed since
        // 1970-01-01 00:00:00 UTC in a 32-bit unsigned integer.
        case TimeStampFormat.ts32:
          final seconds = reader.readUint32();
          return DateTime.fromMillisecondsSinceEpoch(
            seconds * 1000,
            isUtc: true,
          );
        // Timestamp 64: stores the number of seconds and nanoseconds that have
        // elapsed since 1970-01-01 00:00:00 UTC in 32-bit unsigned integers.
        case TimeStampFormat.ts64:
          final nanoSeconds = reader.readUint32();
          final seconds = reader.readUint32();
          return DateTime.fromMillisecondsSinceEpoch(
            seconds * 1000,
            isUtc: true,
          ).add(Duration(microseconds: nanoSeconds ~/ 1000));
        // Timestamp 96: stores the number of seconds and nanoseconds that have
        // elapsed since 1970-01-01 00:00:00 UTC in a 64-bit signed integer and
        // a 32-bit unsigned integer.
        case TimeStampFormat.ts96:
          final nanoSeconds = reader.readUint32();
          final seconds = reader.readInt64();
          return DateTime.fromMillisecondsSinceEpoch(
            seconds * 1000,
            isUtc: true,
          ).add(Duration(microseconds: nanoSeconds ~/ 1000));
      }
    }
    throw UnimplementedError();
  }
}

void main() {
  // Serialize with custom extension
  final date = DateTime.utc(2021, 1, 1, 12, 32, 5, 880, 999);
  final userData = serialize(
    {
      'id': 1,
      'name': 'John Doe',
      'created': date,
      'updated': date.add(const Duration(days: 1)),
    },
    extEncoder: CustomTypesExtEncoder(
      timeStampFormat: TimeStampFormat.ts64,
    ),
  );

  // Deserialize with custom extension
  final deserializedData = deserialize(
    userData,
    extDecoder: CustomTypesExtDecoder(),
  );

  // ignore: avoid_print
  print(deserializedData);
  // Output:
  // {
  //  id: 1,
  //  name: John Doe,
  //  created: 2021-01-01 12:32:05.880999Z,
  //  updated: 2021-01-02 12:32:05.880999Z
  //}
}

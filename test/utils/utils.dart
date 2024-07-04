import 'dart:typed_data';

import 'package:pro_binary/pro_binary.dart';
import 'package:pro_mpack/pro_mpack.dart';

enum TimeStampFormat {
  ts32,
  ts64,
  ts96,
}

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

class CustomTypesExtDecoder implements ExtDecoder {
  @override
  Object? decodeObject(int extType, Uint8List data) {
    if (extType == -1) {
      final reader = BinaryReader(data);
      switch (data.length) {
        // Timestamp 32: stores the number of seconds that have elapsed since
        // 1970-01-01 00:00:00 UTC in a 32-bit unsigned integer.
        case 4:
          final seconds = reader.readUint32();
          return DateTime.fromMillisecondsSinceEpoch(
            seconds * 1000,
            isUtc: true,
          );
        // Timestamp 64: stores the number of seconds and nanoseconds that have
        // elapsed since 1970-01-01 00:00:00 UTC in 32-bit unsigned integers.
        case 8:
          final nanoSeconds = reader.readUint32();
          final seconds = reader.readUint32();
          return DateTime.fromMillisecondsSinceEpoch(
            seconds * 1000,
            isUtc: true,
          ).add(Duration(microseconds: nanoSeconds ~/ 1000));
        // Timestamp 96: stores the number of seconds and nanoseconds that have
        // elapsed since 1970-01-01 00:00:00 UTC in a 64-bit signed integer and
        // a 32-bit unsigned integer.
        case 12:
          final nanoSeconds = reader.readUint32();
          final seconds = reader.readInt64();
          return DateTime.fromMillisecondsSinceEpoch(
            seconds * 1000,
            isUtc: true,
          ).add(Duration(microseconds: nanoSeconds ~/ 1000));
        default:
          throw Exception('Invalid timestamp length');
      }
    }
    throw UnimplementedError();
  }
}

class CustomExtDecoder with ExtDecoder {
  @override
  Object? decodeObject(int extType, Uint8List data) =>
      'Custom ext type $extType with data $data';
}

class CustomExtension {
  CustomExtension(this.type, this.data);
  final int type;
  final Uint8List data;
}

class TestExtEncoder with ExtEncoder {
  @override
  int? extTypeForObject(Object? object) {
    if (object is CustomExtension) {
      return object.type;
    }
    return null;
  }

  @override
  Uint8List encodeObject(Object? object) {
    if (object is CustomExtension) {
      return object.data;
    }

    throw Exception('Unknown object type');
  }
}

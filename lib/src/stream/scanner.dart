import 'package:pro_binary/pro_binary.dart';

import '../core/constants.dart';

/// A zero-allocation scanner for validating MessagePack encoded data.
///
/// This class recursively "walks" through the MessagePack data using the
/// [StreamBinaryReader] without constructing any Dart objects (no strings,
/// no maps, no lists). It just advances the stream offset.
///
/// If it reaches the end of the available bytes prematurely, it relies on
/// the [NotEnoughDataException] thrown by the reader.
abstract final class MessagePackScanner {
  /// Private constructor to prevent instantiation
  MessagePackScanner._();

  /// Skips exactly one MessagePack encoded value.
  ///
  /// Throws [NotEnoughDataException] if there are not enough bytes in the
  /// [reader] to complete the value.
  static void skip(StreamBinaryReader reader) {
    final header = reader.readUint8();

    switch (header) {
      case fNil || fFalse || fTrue:
      case <= limitInt8 || >= fNegFixIntPrefix:
        break;

      case fFloat32:
        reader.skip(4);
      case fFloat64:
        reader.skip(8);
      case fUint8 || fInt8:
        reader.skip(1);
      case fUint16 || fInt16:
        reader.skip(2);
      case fUint32 || fInt32:
        reader.skip(4);
      case fUint64 || fInt64:
        reader.skip(8);

      case >= fFixStrPrefix && <= fFixStrEnd:
        reader.skip(header & fFixStrDataMask);
      case fStr8 || fBin8:
        reader.skip(reader.readUint8());
      case fStr16 || fBin16:
        reader.skip(reader.readUint16());
      case fStr32 || fBin32:
        reader.skip(reader.readUint32());

      case >= fFixArrayPrefix && <= fFixArrayEnd:
        final len = header & fFixCountMask;
        for (var i = 0; i < len; i++) {
          skip(reader);
        }
      case fArray16:
        final len = reader.readUint16();
        for (var i = 0; i < len; i++) {
          skip(reader);
        }
      case fArray32:
        final len = reader.readUint32();
        for (var i = 0; i < len; i++) {
          skip(reader);
        }

      case >= fFixMapPrefix && <= fFixMapEnd:
        final len = header & fFixCountMask;
        for (var i = 0; i < len * 2; i++) {
          skip(reader);
        }
      case fMap16:
        final len = reader.readUint16();
        for (var i = 0; i < len * 2; i++) {
          skip(reader);
        }
      case fMap32:
        final len = reader.readUint32();
        for (var i = 0; i < len * 2; i++) {
          skip(reader);
        }

      case fFixExt1:
        reader.skip(2); // type (1 byte) + data (1 byte)
      case fFixExt2:
        reader.skip(3);
      case fFixExt4:
        reader.skip(5);
      case fFixExt8:
        reader.skip(9);
      case fFixExt16:
        reader.skip(17);
      case fExt8:
        reader.skip(reader.readUint8() + 1);
      case fExt16:
        reader.skip(reader.readUint16() + 1);
      case fExt32:
        reader.skip(reader.readUint32() + 1);

      case fNeverUsed:
        throw const FormatException('Invalid MessagePack format byte 0xc1');
      default:
        throw FormatException(
          'Unknown MessagePack format byte '
          '0x${header.toRadixString(16).padLeft(2, '0')}',
        );
    }
  }
}

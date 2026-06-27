import 'package:pro_binary/pro_binary.dart';

import '../core/constants.dart';
import '../core/grammar.dart';

/// A zero-allocation scanner for validating MessagePack encoded data.
///
/// This class recursively "walks" through the MessagePack data using the
/// [StreamBinaryReader] without constructing any Dart objects (no strings,
/// no maps, no lists). It just advances the stream offset.
///
/// It is a thin skip-walk over the shared wire-format grammar (see
/// `core/grammar.dart`); `Unpacker.skip()` is the same walk over a complete
/// buffer, so the streaming-skip and buffered-skip paths cannot drift.
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

    switch (mpShapes[header]) {
      case MpShape.single:
        break;
      case MpShape.fixed:
        reader.skip(mpFixedSkip[header]);
      case MpShape.fixExt:
        reader.skip(1 + mpFixedSkip[header]); // type byte + data
      case MpShape.fixStr:
        reader.skip(header & fFixStrDataMask);
      case MpShape.strBin8:
        reader.skip(reader.readUint8());
      case MpShape.strBin16:
        reader.skip(reader.readUint16());
      case MpShape.strBin32:
        reader.skip(reader.readUint32());
      case MpShape.fixArray:
        _skipValues(reader, header & fFixCountMask);
      case MpShape.array16:
        _skipValues(reader, reader.readUint16());
      case MpShape.array32:
        _skipValues(reader, reader.readUint32());
      case MpShape.fixMap:
        _skipValues(reader, (header & fFixCountMask) * 2);
      case MpShape.map16:
        _skipValues(reader, reader.readUint16() * 2);
      case MpShape.map32:
        _skipValues(reader, reader.readUint32() * 2);
      case MpShape.ext8:
        reader.skip(reader.readUint8() + 1); // data + type byte
      case MpShape.ext16:
        reader.skip(reader.readUint16() + 1);
      case MpShape.ext32:
        reader.skip(reader.readUint32() + 1);
      case MpShape.neverUsed:
        throw const FormatException('Invalid MessagePack format byte 0xc1');
      case MpShape.unknown:
        throw FormatException(
          'Unknown MessagePack format byte '
          '0x${header.toRadixString(16).padLeft(2, '0')}',
        );
    }
  }

  /// Skips [count] consecutive values (array elements or map keys+values).
  static void _skipValues(StreamBinaryReader reader, int count) {
    for (var i = 0; i < count; i++) {
      skip(reader);
    }
  }
}

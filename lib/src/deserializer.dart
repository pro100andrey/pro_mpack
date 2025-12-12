// Mask constants

import 'dart:typed_data';

import 'package:pro_binary/pro_binary.dart';

import 'constants.dart';
import 'error.dart';

/// A mixin that provides functionality for decoding custom extension types.
///
/// This mixin is intended to be implemented by classes that handle the decoding
/// of custom extension types in MessagePack format. The implementing class must
/// provide the implementation for the `decodeObject` method.
mixin ExtDecoder {
  /// Decodes a custom extension type object.
  ///
  /// This method is called when a custom extension type object is encountered
  /// during deserialization. The method should decode the object based on the
  /// provided extension type and data.
  ///
  /// [extType] is the integer representing the custom extension type.
  /// [data] is the binary data associated with the extension type.
  ///
  /// Returns the decoded object, or `null` if the object could not be decoded.
  ///
  /// Throws an [UnimplementedError] if the extension type is not recognized.
  dynamic decodeObject(int extType, Uint8List data);
}

/// A class responsible for deserializing MessagePack-encoded data.
class Deserializer {
  /// Creates a Deserializer with a given [buffer] and an optional [extDecoder].
  ///
  /// The [buffer] parameter is the binary data to be deserialized.
  /// The [extDecoder] parameter is a function that can decode custom extension
  /// types in the MessagePack format.
  Deserializer(
    Uint8List buffer, {
    ExtDecoder? extDecoder,
  })  : _reader = BinaryReader(buffer),
        _extDecoder = extDecoder;

  final BinaryReader _reader;
  final ExtDecoder? _extDecoder;

  /// Decodes the next value from the buffer.
  ///
  /// Returns an Object representing the deserialized value, which could be
  /// of various types such as int, String, List, Map, or null.
  ///
  /// Throws a [MessagePackError] if the buffer contains invalid MessagePack
  /// format.
  dynamic decode() {
    final u = _reader.readUint8();

    // Formats
    switch (u) {
      // Positive fixint (0x00 - 0x7f): single-byte positive integer
      case <= limitInt8:
        return u;

      // Negative fixint (0xe0 - 0xff): single-byte negative integer
      case >= formatNegFixIntPrefix:
        return u - 256;

      // Fixstr (0xa0 - 0xbf): string with length up to 31 bytes
      case >= formatFixStrPrefix && <= 0xbf:
        return _reader.readString(u & 0x1f);

      // Fixarray (0x90 - 0x9f): array with length up to 15 elements
      case >= formatFixArrayPrefix && <= 0x9f:
        final length = u & 0x0f;

        final list = List<dynamic>.filled(length, null);
        for (var i = 0; i < length; i++) {
          list[i] = decode();
        }
        return list;

      // Fixmap (0x80 - 0x8f): map with length up to 15 key-value pairs
      case >= formatFixMapPrefix && <= 0x8f:
        final map = {};

        for (var i = 0; i < u & 0x0f; i++) {
          final key = decode();
          final value = decode();
          map[key] = value;
        }

        return map;
      // Nil (0xc0): null value
      case formatNil:
        return null;
      // False (0xc2): boolean false
      case formatFalse:
        return false;
      // True (0xc3): boolean true
      case formatTrue:
        return true;
      // uint8 (0xcc): 8-bit unsigned integer
      case formatUint8:
        return _reader.readUint8();
      // uint16 (0xcd): 16-bit big-endian unsigned integer
      case formatUint16:
        return _reader.readUint16();
      // uint32 (0xce): 32-bit big-endian unsigned integer
      case formatUint32:
        return _reader.readUint32();
      // uint64 (0xcf): 64-bit big-endian unsigned integer
      case formatUint64:
        return _reader.readUint64();
      // int8 (0xd0): 8-bit signed integer
      case formatInt8:
        return _reader.readInt8();
      // int16 (0xd1): 16-bit big-endian signed integer
      case formatInt16:
        return _reader.readInt16();
      // int32 (0xd2): 32-bit big-endian signed integer
      case formatInt32:
        return _reader.readInt32();
      // int64 (0xd3): 64-bit big-endian signed integer
      case formatInt64:
        return _reader.readInt64();
      // float32 (0xca): 32-bit floating point number (IEEE 754)
      case formatFloat32:
        return _reader.readFloat32();
      // float64 (0xcb): 64-bit floating point number (IEEE 754)
      case formatFloat64:
        return _reader.readFloat64();
      // str8 (0xd9): string with length up to 255 bytes
      case formatStr8:
        return _reader.readString(_reader.readUint8());
      // str16 (0xda): string with length up to 65535 bytes
      case formatStr16:
        return _reader.readString(_reader.readUint16());
      // str32 (0xdb): string with length up to 4294967295 bytes
      case formatStr32:
        return _reader.readString(_reader.readUint32());
      // bin8 (0xc4): binary data with length up to 255 bytes
      case formatBin8:
        return _reader.readBytes(_reader.readUint8());
      // bin16 (0xc5): binary data with length up to 65535 bytes
      case formatBin16:
        return _reader.readBytes(_reader.readUint16());
      // bin32 (0xc6): binary data with length up to 4294967295 bytes
      case formatBin32:
        return _reader.readBytes(_reader.readUint32());
      // array16 (0xdc): array with length up to 65535 elements
      case formatArray16:
        final length = _reader.readUint16();

        final list = List<dynamic>.filled(length, null);
        for (var i = 0; i < length; i++) {
          list[i] = decode();
        }
        return list;
      // array32 (0xdd): array with length up to 4294967295 elements
      case formatArray32:
        final length = _reader.readUint32();

        final list = List<dynamic>.filled(length, null);
        for (var i = 0; i < length; i++) {
          list[i] = decode();
        }
        return list;
      // map16 (0xde): map with length up to 65535 key-value pairs
      case formatMap16:
        final length = _reader.readUint16();
        final map = {};

        for (var i = 0; i < length; i++) {
          final key = decode();
          final value = decode();
          map[key] = value;
        }

        return map;
      // map32 (0xdf): map with length up to 4294967295 key-value pairs
      case formatMap32:
        final length = _reader.readUint32();
        final map = {};

        for (var i = 0; i < length; i++) {
          final key = decode();
          final value = decode();
          map[key] = value;
        }

        return map;
      // fixext1 (0xd4): extension with 1 byte of data
      case formatFixExt1:
        return _readExt(1);
      // fixext2 (0xd5): extension with 2 bytes of data
      case formatFixExt2:
        return _readExt(2);
      // fixext4 (0xd6): extension with 4 bytes of data
      case formatFixExt4:
        return _readExt(4);
      // fixext8 (0xd7): extension with 8 bytes of data
      case formatFixExt8:
        return _readExt(8);
      // fixext16 (0xd8): extension with 16 bytes of data
      case formatFixExt16:
        return _readExt(16);
      // ext8 (0xc7): extension with length up to 255 bytes
      case formatExt8:
        return _readExt(_reader.readUint8());
      // ext16 (0xc8): extension with length up to 65535 bytes
      case formatExt16:
        return _readExt(_reader.readUint16());
      // ext32 (0xc9): extension with length up to 4294967295 bytes
      case formatExt32:
        return _readExt(_reader.readUint32());
      // Default case: invalid MessagePack format
      default:
        throw MessagePackError('Invalid MessagePack format');
    }
  }

  dynamic _readExt(int length) {
    final extType = _reader.readInt8();
    final data = _reader.readBytes(length);

    if (extType == extTypeTimestamp) {
      return _decodeTimestamp(data);
    }

    return _extDecoder?.decodeObject(extType, data);
  }

  DateTime _decodeTimestamp(Uint8List data) {
    switch (data.length) {
      case 4:
        final reader = BinaryReader(data);
        final seconds = reader.readUint32();
        return DateTime.fromMillisecondsSinceEpoch(
          seconds * 1000,
          isUtc: true,
        );
      case 8:
        final reader = BinaryReader(data);
        final data64 = reader.readUint64();
        final nanoSeconds = data64 >> 34; // top 30 bits
        final seconds = data64 & 0x3FFFFFFFF; // bottom 34 bits
        return DateTime.fromMillisecondsSinceEpoch(
          seconds * 1000,
          isUtc: true,
        ).add(Duration(microseconds: nanoSeconds ~/ 1000));
      case 12:
        final reader = BinaryReader(data);
        final nanoSeconds = reader.readUint32();
        final seconds = reader.readInt64();
        return DateTime.fromMillisecondsSinceEpoch(
          seconds * 1000,
          isUtc: true,
        ).add(Duration(microseconds: nanoSeconds ~/ 1000));
      default:
        throw MessagePackError('Invalid timestamp length: ${data.length}');
    }
  }
}

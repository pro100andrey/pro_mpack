// Mask constants

import 'dart:convert';
import 'dart:typed_data';

import 'package:pro_binary/pro_binary.dart';

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
  Object? decodeObject(int extType, Uint8List data);
}

/// A class responsible for deserializing MessagePack-encoded data.
class Deserializer {
  /// Creates a Deserializer with a given [buffer] and an optional [extDecoder].
  ///
  /// The [buffer] parameter is the binary data to be deserialized.
  /// The [extDecoder] parameter is a function that can decode custom extension
  /// types in the MessagePack format.
  Deserializer(
    Uint8List buffer, [
    ExtDecoder? extDecoder,
  ])  : _reader = BinaryReader(buffer),
        _extDecoder = extDecoder;

  final BinaryReader _reader;
  final ExtDecoder? _extDecoder;

  /// Decodes the next value from the buffer.
  ///
  /// Returns an Object representing the deserialized value, which could be
  /// of various types such as int, String, List, Map, or null.
  ///
  /// Throws an Exception if the buffer contains invalid MessagePack format.
  Object? decode() {
    final u = _reader.readUint8();

    // Positive fixint (0x00 - 0x7f): single-byte positive integer
    if (u <= 0x7f) {
      return u;
    }
    // Negative fixint (0xe0 - 0xff): single-byte negative integer
    else if ((u & 0xe0) == 0xe0) {
      return u - 256;
    }
    // Fixstr (0xa0 - 0xbf): string with length up to 31 bytes
    else if ((u & 0xe0) == 0xa0) {
      return _readString(u & 0x1f);
    }
    // Fixarray (0x90 - 0x9f): array with length up to 15 elements
    else if ((u & 0xf0) == 0x90) {
      return List.generate(u & 0x0f, (_) => decode());
    }
    // Fixmap (0x80 - 0x8f): map with length up to 15 key-value pairs
    else if ((u & 0xf0) == 0x80) {
      return {
        for (var i = 0; i < u & 0x0f; i++) decode(): decode(),
      };
    }

    // Other formats
    switch (u) {
      // Nil (0xc0): null value
      case 0xc0:
        return null;
      // False (0xc2): boolean false
      case 0xc2:
        return false;
      // True (0xc3): boolean true
      case 0xc3:
        return true;
      // uint8 (0xcc): 8-bit unsigned integer
      case 0xcc:
        return _reader.readUint8();
      // uint16 (0xcd): 16-bit big-endian unsigned integer
      case 0xcd:
        return _reader.readUint16();
      // uint32 (0xce): 32-bit big-endian unsigned integer
      case 0xce:
        return _reader.readUint32();
      // uint64 (0xcf): 64-bit big-endian unsigned integer
      case 0xcf:
        return _reader.readUint64();
      // int8 (0xd0): 8-bit signed integer
      case 0xd0:
        return _reader.readInt8();
      // int16 (0xd1): 16-bit big-endian signed integer
      case 0xd1:
        return _reader.readInt16();
      // int32 (0xd2): 32-bit big-endian signed integer
      case 0xd2:
        return _reader.readInt32();
      // int64 (0xd3): 64-bit big-endian signed integer
      case 0xd3:
        return _reader.readInt64();
      // float32 (0xca): 32-bit floating point number (IEEE 754)
      case 0xca:
        return _reader.readFloat32();
      // float64 (0xcb): 64-bit floating point number (IEEE 754)
      case 0xcb:
        return _reader.readFloat64();
      // str8 (0xd9): string with length up to 255 bytes
      case 0xd9:
        return _readString(_reader.readUint8());
      // str16 (0xda): string with length up to 65535 bytes
      case 0xda:
        return _readString(_reader.readUint16());
      // str32 (0xdb): string with length up to 4294967295 bytes
      case 0xdb:
        return _readString(_reader.readUint32());
      // bin8 (0xc4): binary data with length up to 255 bytes
      case 0xc4:
        return _reader.readBytes(_reader.readUint8());
      // bin16 (0xc5): binary data with length up to 65535 bytes
      case 0xc5:
        return _reader.readBytes(_reader.readUint16());
      // bin32 (0xc6): binary data with length up to 4294967295 bytes
      case 0xc6:
        return _reader.readBytes(_reader.readUint32());
      // array16 (0xdc): array with length up to 65535 elements
      case 0xdc:
        final length = _reader.readUint16();
        return List.generate(length, (_) => decode());
      // array32 (0xdd): array with length up to 4294967295 elements
      case 0xdd:
        final length = _reader.readUint32();
        return List.generate(length, (_) => decode());
      // map16 (0xde): map with length up to 65535 key-value pairs
      case 0xde:
        final length = _reader.readUint16();
        return {
          for (var i = 0; i < length; i++) decode(): decode(),
        };
      // map32 (0xdf): map with length up to 4294967295 key-value pairs
      case 0xdf:
        final length = _reader.readUint32();
        return {
          for (var i = 0; i < length; i++) decode(): decode(),
        };
      // fixext1 (0xd4): extension with 1 byte of data
      case 0xd4:
        return _readExt(1);
      // fixext2 (0xd5): extension with 2 bytes of data
      case 0xd5:
        return _readExt(2);
      // fixext4 (0xd6): extension with 4 bytes of data
      case 0xd6:
        return _readExt(4);
      // 0xd7 (0xd7): extension with 8 bytes of data
      case 0xd7:
        return _readExt(8);
      // fixext16 (0xd8): extension with 16 bytes of data
      case 0xd8:
        return _readExt(16);
      // ext8 (0xc7): extension with length up to 255 bytes
      case 0xc7:
        return _readExt(_reader.readUint8());
      // ext16 (0xc8): extension with length up to 65535 bytes
      case 0xc8:
        return _readExt(_reader.readUint16());
      // ext32 (0xc9): extension with length up to 4294967295 bytes
      case 0xc9:
        return _readExt(_reader.readUint32());
      // Default case: invalid MessagePack format
      default:
        throw Exception('Invalid MessagePack format');
    }
  }

  String _readString(int length) {
    // Read the specified number of bytes from the reader
    final bytes = _reader.readBytes(length);
    // Check if the byte array contains any non-ASCII characters
    // ASCII characters have values in the range 0-127
    // If any byte has a value greater than 127, it means the string contains
    // non-ASCII characters
    if (bytes.any((byte) => byte > 127)) {
      // Decode the byte array using UTF-8 to properly handle non-ASCII
      // characters
      return utf8.decode(bytes);
    }

    // If all characters are ASCII, convert the byte array to a string directly
    return String.fromCharCodes(bytes);
  }

  Object? _readExt(int length) {
    final extType = _reader.readInt8();
    final data = _reader.readBytes(length);

    return _extDecoder?.decodeObject(extType, data);
  }
}

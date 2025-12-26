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
  Object? decodeObject(int extType, Uint8List data);
}

/// A class responsible for deserializing MessagePack-encoded data.
///
/// The [Deserializer] class provides a low-level interface for decoding
/// MessagePack binary data into Dart objects. It maintains an internal
/// reader that tracks the current position in the buffer.
///
/// ## Usage
///
/// For most use cases, prefer the high-level `deserialize()` function. Use
/// [Deserializer] directly when you need to decode multiple values from a
/// single buffer:
///
/// ```dart
/// final deserializer = Deserializer(bytes);
/// while (deserializer.hasBytesAvailable) {
///   final value = deserializer.decode();
///   print(value);
/// }
/// ```
///
/// The deserializer automatically handles all MessagePack types and formats,
/// including nested structures and extension types.
class Deserializer {
  /// Creates a [Deserializer] with a given [buffer] and an optional
  /// [extDecoder].
  ///
  /// [buffer]: The MessagePack-encoded binary data to deserialize.
  ///
  /// [extDecoder]: Optional decoder for custom extension types. When
  /// provided, extension types (other than the built-in timestamp type -1)
  /// will be decoded using this decoder.
  Deserializer(
    Uint8List buffer, {
    ExtDecoder? extDecoder,
  }) : _reader = BinaryReader(buffer),
       _extDecoder = extDecoder;

  final BinaryReader _reader;
  final ExtDecoder? _extDecoder;

  /// Returns `true` if there are unread bytes remaining in the buffer.
  ///
  /// This property is useful when deserializing multiple consecutive values
  /// from a single buffer:
  ///
  /// ```dart
  /// final deserializer = Deserializer(buffer);
  /// while (deserializer.hasBytesAvailable) {
  ///   final value = deserializer.decode();
  ///   processValue(value);
  /// }
  /// ```
  bool get hasBytesAvailable => _reader.availableBytes > 0;

  /// Decodes the next value from the buffer.
  ///
  /// This method reads the next MessagePack value from the current position
  /// in the buffer and advances the position. The type of the returned value
  /// depends on the MessagePack format:
  ///
  /// - nil (0xc0) → `null`
  /// - bool (0xc2, 0xc3) → `bool`
  /// - fixint, int8/16/32/64 → `int`
  /// - float32/64 → `double`
  /// - fixstr, str8/16/32 → `String`
  /// - bin8/16/32 → `Uint8List`
  /// - fixarray, array16/32 → `List<Object?>`
  /// - fixmap, map16/32 → `Map<Object?, Object?>`
  /// - timestamp ext (-1) → `DateTime`
  /// - other extensions → decoded via [ExtDecoder] if provided
  ///
  /// Example:
  /// ```dart
  /// final deserializer = Deserializer(buffer);
  /// final value = deserializer.decode();
  /// ```
  ///
  /// Returns the deserialized object, which may be `null`, a primitive
  /// type, a collection, or a custom type from an extension decoder.
  ///
  /// Throws [MessagePackError] if the buffer contains invalid MessagePack
  /// format or if there are insufficient bytes to read.
  Object? decode() {
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
        return _decodeArray(u & 0x0f);

      // Fixmap (0x80 - 0x8f): map with length up to 15 key-value pairs
      case >= formatFixMapPrefix && <= 0x8f:
        return _decodeMap(u & 0x0f);
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
        return _decodeArray(_reader.readUint16());
      // array32 (0xdd): array with length up to 4294967295 elements
      case formatArray32:
        return _decodeArray(_reader.readUint32());
      // map16 (0xde): map with length up to 65535 key-value pairs
      case formatMap16:
        return _decodeMap(_reader.readUint16());
      // map32 (0xdf): map with length up to 4294967295 key-value pairs
      case formatMap32:
        return _decodeMap(_reader.readUint32());
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

  @pragma('vm:prefer-inline')
  @pragma('dart2js:tryInline')
  Map<Object?, Object?> _decodeMap(int length) {
    final map = <Object?, Object?>{};

    for (var i = 0; i < length; i++) {
      final key = decode();
      final value = decode();
      map[key] = value;
    }

    return map;
  }

  @pragma('vm:prefer-inline')
  @pragma('dart2js:tryInline')
  List<Object?> _decodeArray(int length) {
    final list = List<Object?>.filled(length, null);
    for (var i = 0; i < length; i++) {
      list[i] = decode();
    }
    return list;
  }

  @pragma('vm:prefer-inline')
  @pragma('dart2js:tryInline')
  Object? _readExt(int length) {
    final extType = _reader.readInt8();
    final data = _reader.readBytes(length);

    if (extType == extTypeTimestamp) {
      return _decodeTimestamp(data);
    }

    return _extDecoder?.decodeObject(extType, data);
  }

  @pragma('vm:prefer-inline')
  @pragma('dart2js:tryInline')
  DateTime _decodeTimestamp(Uint8List data) {
    final view = ByteData.view(
      data.buffer,
      data.offsetInBytes,
      data.lengthInBytes,
    );
    switch (data.length) {
      case 4:
        final seconds = view.getUint32(0);
        return DateTime.fromMillisecondsSinceEpoch(
          seconds * 1000,
          isUtc: true,
        );
      case 8:
        final data64 = view.getUint64(0);
        final nanoSeconds = (data64 >> 34) & 0x3FFFFFFF;
        final seconds = data64 & 0x3FFFFFFFF;
        return DateTime.fromMillisecondsSinceEpoch(
          seconds * 1000,
          isUtc: true,
        ).add(Duration(microseconds: nanoSeconds ~/ 1000));
      case 12:
        final nanoSeconds = view.getUint32(0);
        final seconds = view.getInt64(4);
        return DateTime.fromMillisecondsSinceEpoch(
          seconds * 1000,
          isUtc: true,
        ).add(Duration(microseconds: nanoSeconds ~/ 1000));
      default:
        throw MessagePackError('Invalid timestamp length: ${data.length}');
    }
  }
}

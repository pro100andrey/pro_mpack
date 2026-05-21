// Mask constants

import 'dart:collection';
import 'dart:typed_data';

import 'package:pro_binary/pro_binary.dart';

import 'constants.dart';
import 'error.dart';

/// A mixin that provides functionality for decoding custom extension types.
///
/// This mixin is intended to be implemented by classes that handle the decoding
/// of custom extension types in MessagePack format. The implementing class must
/// provide the implementation for the `decodeObject` method.
abstract mixin class ExtDecoder {
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
  ///
  /// [preserveMapOrder]: If `true`, maps will preserve the insertion order
  /// of their key-value pairs. Defaults to `false`, which uses a standard
  /// `HashMap` that does not guarantee order.
  Deserializer(
    Uint8List buffer, {
    ExtDecoder? extDecoder,
    bool? preserveMapOrder,
  }) : _reader = BinaryReader(buffer),
       _extDecoder = extDecoder,
       _preserveMapOrder = preserveMapOrder ?? false;

  final BinaryReader _reader;
  final ExtDecoder? _extDecoder;
  final bool _preserveMapOrder;

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
      case <= limitInt8:
        // Positive fixint (0x00 - 0x7f): single-byte positive integer
        return u;

      case >= fNegFixIntPrefix:
        // Negative fixint (0xe0 - 0xff): single-byte negative integer
        return u - 256;

      // Fixstr (0xa0 - 0xbf): string with length up to 31 bytes
      case >= fFixStrPrefix && <= fFixStrEnd:
        return _reader.readString(u & fFixStrDataMask);

      // Fixarray (0x90 - 0x9f): array with length up to 15 elements
      case >= fFixArrayPrefix && <= fFixArrayEnd:
        return _decodeArray(u & fFixCountMask);

      // Fixmap (0x80 - 0x8f): map with length up to 15 key-value pairs
      case >= fFixMapPrefix && <= fFixMapEnd:
        return _decodeMap(u & fFixCountMask);

      // Nil (0xc0): null value
      case fNil:
        return null;

      // False (0xc2): boolean false
      case fFalse:
        return false;
      // True (0xc3): boolean true
      case fTrue:
        return true;

      // bin8 (0xc4): binary data with length up to 255 bytes
      case fBin8:
        return _reader.readBytes(_reader.readUint8());
      // bin16 (0xc5): binary data with length up to 65535 bytes
      case fBin16:
        return _reader.readBytes(_reader.readUint16());
      // bin32 (0xc6): binary data with length up to 4294967295 bytes
      case fBin32:
        return _reader.readBytes(_reader.readUint32());

      // ext8 (0xc7): extension with length up to 255 bytes
      case fExt8:
        return _readExt(_reader.readUint8());
      // ext16 (0xc8): extension with length up to 65535 bytes
      case fExt16:
        return _readExt(_reader.readUint16());
      // ext32 (0xc9): extension with length up to 4294967295 bytes
      case fExt32:
        return _readExt(_reader.readUint32());

      // float32 (0xca): 32-bit floating point number (IEEE 754)
      case fFloat32:
        return _reader.readFloat32();
      // float64 (0xcb): 64-bit floating point number (IEEE 754)
      case fFloat64:
        return _reader.readFloat64();

      // uint8 (0xcc): 8-bit unsigned integer
      case fUint8:
        return _reader.readUint8();
      // uint16 (0xcd): 16-bit big-endian unsigned integer
      case fUint16:
        return _reader.readUint16();
      // uint32 (0xce): 32-bit big-endian unsigned integer
      case fUint32:
        return _reader.readUint32();
      // uint64 (0xcf): 64-bit big-endian unsigned integer
      case fUint64:
        return _reader.readUint64();

      // int8 (0xd0): 8-bit signed integer
      case fInt8:
        return _reader.readInt8();
      // int16 (0xd1): 16-bit big-endian signed integer
      case fInt16:
        return _reader.readInt16();
      // int32 (0xd2): 32-bit big-endian signed integer
      case fInt32:
        return _reader.readInt32();
      // int64 (0xd3): 64-bit big-endian signed integer
      case fInt64:
        return _reader.readInt64();

      // fixext1 (0xd4): extension with 1 byte of data
      case fFixExt1:
        return _readExt(1);
      // fixext2 (0xd5): extension with 2 bytes of data
      case fFixExt2:
        return _readExt(2);
      // fixext4 (0xd6): extension with 4 bytes of data
      case fFixExt4:
        return _readExt(4);
      // fixext8 (0xd7): extension with 8 bytes of data
      case fFixExt8:
        return _readExt(8);
      // fixext16 (0xd8): extension with 16 bytes of data
      case fFixExt16:
        return _readExt(16);

      // str8 (0xd9): string with length up to 255 bytes
      case fStr8:
        return _reader.readString(_reader.readUint8());
      // str16 (0xda): string with length up to 65535 bytes
      case fStr16:
        return _reader.readString(_reader.readUint16());
      // str32 (0xdb): string with length up to 4294967295 bytes
      case fStr32:
        return _reader.readString(_reader.readUint32());

      // array16 (0xdc): array with length up to 65535 elements
      case fArray16:
        return _decodeArray(_reader.readUint16());
      // array32 (0xdd): array with length up to 4294967295 elements
      case fArray32:
        return _decodeArray(_reader.readUint32());

      // map16 (0xde): map with length up to 65535 key-value pairs
      case fMap16:
        return _decodeMap(_reader.readUint16());
      // map32 (0xdf): map with length up to 4294967295 key-value pairs
      case fMap32:
        return _decodeMap(_reader.readUint32());

      // Never used (0xc1): reserved by MessagePack specification
      case fNeverUsed:
        throw MessagePackError(
          'Invalid format byte 0xc1: this value is reserved and never used '
          'in MessagePack specification',
        );
      // Default case: invalid MessagePack format
      default:
        throw MessagePackError('Invalid MessagePack format');
    }
  }

  @pragma('vm:prefer-inline')
  Map<Object?, Object?> _decodeMap(int length) {
    if (length == 0) {
      return const {};
    }

    final map = _preserveMapOrder
        ? <Object?, Object?>{}
        : HashMap<Object?, Object?>();

    for (var i = 0; i < length; i++) {
      final key = decode();
      map[key] = decode();
    }

    return map;
  }

  @pragma('vm:prefer-inline')
  List<Object?> _decodeArray(int length) {
    if (length == 0) {
      return const [];
    }

    final result = List<Object?>.filled(length, null);
    for (var i = 0; i < length; i++) {
      result[i] = decode();
    }

    return result;
  }

  @pragma('vm:prefer-inline')
  Object? _readExt(int length) {
    final extType = _reader.readInt8();

    if (extType == extTypeTimestamp) {
      return _decodeTimestamp(length);
    }

    final data = _reader.readBytes(length);
    return _extDecoder?.decodeObject(extType, data);
  }

  @pragma('vm:prefer-inline')
  DateTime _decodeTimestamp(int length) {
    switch (length) {
      case 4:
        final seconds = _reader.readUint32();
        return .fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);
      case 8:
        final data64 = _reader.readUint64();
        final nanoSeconds = (data64 >> 34) & 0x3FFFFFFF;
        final seconds = data64 & 0x3FFFFFFFF;
        final microseconds = seconds * 1000000 + nanoSeconds ~/ 1000;
        return .fromMicrosecondsSinceEpoch(microseconds, isUtc: true);
      case 12:
        final nanoSeconds = _reader.readUint32();
        final seconds = _reader.readInt64();
        final microseconds = seconds * 1000000 + nanoSeconds ~/ 1000;
        return .fromMicrosecondsSinceEpoch(microseconds, isUtc: true);
      default:
        throw MessagePackError('Invalid timestamp length: $length');
    }
  }
}

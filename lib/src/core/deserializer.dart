/// Components for MessagePack deserialization.
library;

import 'dart:collection';
import 'dart:typed_data';

import 'package:pro_binary/pro_binary.dart';

import 'constants.dart';
import 'exception.dart';

/// A mixin that defines the interface for decoding custom extension types.
///
/// Classes that want to support custom MessagePack extensions should implement
/// this mixin. It provides a method to decode a custom extension's binary
/// payload back into a Dart object.
abstract mixin class ExtDecoder {
  /// Decodes a custom extension object from its [data] payload.
  ///
  /// [extType] is the type code of the extension (-128 to 127).
  /// [data] is the binary payload associated with the extension.
  ///
  /// Returns the decoded Dart object.
  ///
  /// Throws a [MessagePackException] if decoding fails or if the extension type
  /// is not recognized.
  Object? decodeObject(int extType, Uint8List data);
}

/// A class for decoding MessagePack binary data into Dart objects.
///
/// [Deserializer] provides a stateful way to decode one or more values from
/// a provided binary buffer. It tracks the current reading position.
///
/// Example:
/// ```dart
/// final deserializer = Deserializer(bytes);
/// while (deserializer.hasBytesAvailable) {
///   final value = deserializer.decode();
///   print(value);
/// }
/// ```
class Deserializer {
  /// Creates a [Deserializer] instance for the provided [buffer].
  ///
  /// [extDecoder] provides support for custom extension types.
  /// [preserveMapOrder] if true, uses a standard [Map] (LinkedHashMap) to
  /// maintain the order of keys as they appear in the MessagePack data.
  /// If false, uses [HashMap] for potentially better performance.
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

  /// Whether there are more bytes to read in the buffer.
  bool get hasBytesAvailable => _reader.availableBytes > 0;

  /// Decodes the next value from the buffer.
  ///
  /// Reads the appropriate number of bytes based on the MessagePack format
  /// prefix and returns the corresponding Dart object.
  ///
  /// Supported types include:
  /// - nil -> `null`
  /// - bool -> `bool`
  /// - int -> `int`
  /// - float 32/64 -> `double`
  /// - str -> `String`
  /// - bin -> `Uint8List`
  /// - array -> `List<Object?>`
  /// - map -> `Map<Object?, Object?>`
  /// - timestamp -> `DateTime`
  /// - Custom types via [ExtDecoder]
  ///
  /// Throws a [MessagePackException] if the data is invalid or the buffer ends
  /// unexpectedly.
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

      // Default case (0xc1 or other invalid): reserved by MessagePack
      // specification or invalid byte.
      default:
        if (u == fNeverUsed) {
          throw const MessagePackFormatException(
            'Invalid format byte 0xc1: this value is reserved and never used '
                'in MessagePack specification',
            'Ensure the data source is valid MessagePack and the stream '
                'is not corrupted.',
          );
        }
        throw MessagePackFormatException(
          'Invalid MessagePack format byte: '
              '0x${u.toRadixString(16).padLeft(2, "0")}',
          'The data might be corrupted or not in MessagePack format.',
        );
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
        return DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);
      case 8:
        final data64 = _reader.readUint64();
        final nanoSeconds = (data64 >> 34) & 0x3FFFFFFF;
        final seconds = data64 & 0x3FFFFFFFF;
        final microseconds = seconds * 1000000 + nanoSeconds ~/ 1000;
        return DateTime.fromMicrosecondsSinceEpoch(microseconds, isUtc: true);
      case 12:
        final nanoSeconds = _reader.readUint32();
        final seconds = _reader.readInt64();
        final microseconds = seconds * 1000000 + nanoSeconds ~/ 1000;
        return DateTime.fromMicrosecondsSinceEpoch(microseconds, isUtc: true);
      default:
        throw MessagePackFormatException(
          'Invalid timestamp length: $length',
          'Timestamps must be 4, 8, or 12 bytes long according to the spec.',
        );
    }
  }
}

/// MessagePack deserializer with a single-callback extension interface.
///
/// Key difference from [../core/deserializer.dart]:
/// Uses a simple [DecodeExt] function typedef instead of the `ExtDecoder`
/// abstract mixin class. Same functionality, less ceremony.
library;

import 'dart:collection';
import 'dart:typed_data';

import 'package:pro_binary/pro_binary.dart';

import '../core/constants.dart';
import '../core/exception.dart';

/// Called by the [Deserializer] when it encounters a MessagePack ext type.
///
/// [type] is the extension type code (-128..127).
/// [data] is the raw binary payload.
///
/// Should return the decoded Dart object.
typedef DecodeExt = Object? Function(int type, Uint8List data);

/// A class for decoding MessagePack binary data into Dart objects.
///
/// Uses a simple [DecodeExt] function instead of the `ExtDecoder` mixin.
///
/// Example:
/// ```dart
/// final d = Deserializer(
///   bytes,
///   decodeExt: (type, data) => switch (type) {
///     1 => decodeMyType(data),
///     _ => throw Exception('Unknown ext: $type'),
///   },
/// );
/// final value = d.decode();
/// ```
class Deserializer {
  /// Creates a [Deserializer] for the provided [buffer].
  ///
  /// [decodeExt] — callback for custom extension types.
  /// [preserveMapOrder] — if `true`, maps use insertion-ordered
  /// [LinkedHashMap]; if `false` (default), uses [HashMap].
  Deserializer(
    Uint8List buffer, {
    DecodeExt? decodeExt,
    bool preserveMapOrder = false,
  }) : _reader = BinaryReader(buffer),
       _decodeExt = decodeExt,
       _preserveMapOrder = preserveMapOrder;

  final BinaryReader _reader;
  final DecodeExt? _decodeExt;
  final bool _preserveMapOrder;

  /// Whether there are more bytes to read in the buffer.
  bool get hasBytesAvailable => _reader.availableBytes > 0;

  /// Decodes the next value from the buffer.
  ///
  /// Returns the corresponding Dart object:
  /// - nil → `null`
  /// - bool → `bool`
  /// - int → `int`
  /// - float 32/64 → `double`
  /// - str → `String`
  /// - bin → `Uint8List`
  /// - array → `List<Object?>`
  /// - map → `Map<Object?, Object?>`
  /// - timestamp → `DateTime`
  /// - ext → result of [DecodeExt] callback
  ///
  /// Throws a [MessagePackException] if the data is invalid.
  Object? decode() {
    final u = _reader.readUint8();

    switch (u) {
      // Positive fixint (0x00 - 0x7f)
      case <= limitInt8:
        return u;

      // Negative fixint (0xe0 - 0xff)
      case >= fNegFixIntPrefix:
        return u - 256;

      // Fixstr (0xa0 - 0xbf)
      case >= fFixStrPrefix && <= fFixStrEnd:
        return _reader.readString(u & fFixStrDataMask);

      // Fixarray (0x90 - 0x9f)
      case >= fFixArrayPrefix && <= fFixArrayEnd:
        return _decodeArray(u & fFixCountMask);

      // Fixmap (0x80 - 0x8f)
      case >= fFixMapPrefix && <= fFixMapEnd:
        return _decodeMap(u & fFixCountMask);

      // Nil
      case fNil:
        return null;

      // Boolean
      case fFalse:
        return false;
      case fTrue:
        return true;

      // Binary
      case fBin8:
        return _reader.readBytes(_reader.readUint8());
      case fBin16:
        return _reader.readBytes(_reader.readUint16());
      case fBin32:
        return _reader.readBytes(_reader.readUint32());

      // Extension
      case fExt8:
        return _readExt(_reader.readUint8());
      case fExt16:
        return _readExt(_reader.readUint16());
      case fExt32:
        return _readExt(_reader.readUint32());

      // Floats
      case fFloat32:
        return _reader.readFloat32();
      case fFloat64:
        return _reader.readFloat64();

      // Unsigned integers
      case fUint8:
        return _reader.readUint8();
      case fUint16:
        return _reader.readUint16();
      case fUint32:
        return _reader.readUint32();
      case fUint64:
        return _reader.readUint64();

      // Signed integers
      case fInt8:
        return _reader.readInt8();
      case fInt16:
        return _reader.readInt16();
      case fInt32:
        return _reader.readInt32();
      case fInt64:
        return _reader.readInt64();

      // Fixed-length extensions
      case fFixExt1:
        return _readExt(1);
      case fFixExt2:
        return _readExt(2);
      case fFixExt4:
        return _readExt(4);
      case fFixExt8:
        return _readExt(8);
      case fFixExt16:
        return _readExt(16);

      // Strings
      case fStr8:
        return _reader.readString(_reader.readUint8());
      case fStr16:
        return _reader.readString(_reader.readUint16());
      case fStr32:
        return _reader.readString(_reader.readUint32());

      // Arrays
      case fArray16:
        return _decodeArray(_reader.readUint16());
      case fArray32:
        return _decodeArray(_reader.readUint32());

      // Maps
      case fMap16:
        return _decodeMap(_reader.readUint16());
      case fMap32:
        return _decodeMap(_reader.readUint32());

      // Reserved / invalid
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
    return _decodeExt?.call(extType, data);
  }

  @pragma('vm:prefer-inline')
  DateTime _decodeTimestamp(int length) {
    switch (length) {
      case 4:
        final seconds = _reader.readUint32();
        return DateTime.fromMillisecondsSinceEpoch(
          seconds * 1000,
          isUtc: true,
        );
      case 8:
        final data64 = _reader.readUint64();
        final nanoSeconds = (data64 >> 34) & 0x3FFFFFFF;
        final seconds = data64 & 0x3FFFFFFFF;
        final microseconds = seconds * 1000000 + nanoSeconds ~/ 1000;
        return DateTime.fromMicrosecondsSinceEpoch(
          microseconds,
          isUtc: true,
        );
      case 12:
        final nanoSeconds = _reader.readUint32();
        final seconds = _reader.readInt64();
        final microseconds = seconds * 1000000 + nanoSeconds ~/ 1000;
        return DateTime.fromMicrosecondsSinceEpoch(
          microseconds,
          isUtc: true,
        );
      default:
        throw MessagePackFormatException(
          'Invalid timestamp length: $length',
          'Timestamps must be 4, 8, or 12 bytes long according to the spec.',
        );
    }
  }

  
}

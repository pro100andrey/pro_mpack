/// MessagePack deserializer.
///
/// Uses a [DecodeExt] function to handle MessagePack extension types.
library;

import 'dart:collection';
import 'dart:typed_data';

import 'package:pro_binary/pro_binary.dart';

import '../../pro_mpack.dart' show Packer;
import 'constants.dart';
import 'exception.dart';
import 'packer.dart' show Packer;

/// Called by the [Unpacker] when it encounters a MessagePack ext type.
///
/// [type] is the extension type code (-128..127).
/// [data] is the raw binary payload.
///
/// Should return the decoded Dart object.
typedef DecodeExt = Object? Function(int type, Uint8List data);

typedef _Internal = ({
  BinaryReader reader,
  DecodeExt? decodeExt,
  bool preserveMapOrder,
});

extension type Unpacker._(_Internal _i) {
  Unpacker({
    required Uint8List buffer,
    DecodeExt? decodeExt,
    bool preserveMapOrder = false,
  }) : _i = (
         reader: BinaryReader(buffer),
         decodeExt: decodeExt,
         preserveMapOrder: preserveMapOrder,
       );

  BinaryReader get _rd => _i.reader;
  DecodeExt? get _ext => _i.decodeExt;
  bool get hasBytesAvailable => _rd.availableBytes > 0;

  @pragma('vm:prefer-inline')
  int unpackInt() => _unpackInt(_rd.readUint8());

  @pragma('vm:prefer-inline')
  double unpackDouble() => _unpackDouble(_rd.readUint8());

  @pragma('vm:prefer-inline')
  bool unpackBool() => _unpackBool(_rd.readUint8());

  @pragma('vm:prefer-inline')
  String unpackString() => _unpackString(_rd.readUint8());

  @pragma('vm:prefer-inline')
  Uint8List unpackBinary() => _unpackBinary(_rd.readUint8());

  @pragma('vm:prefer-inline')
  List<Object?> unpackArray() => _unpackArray(_rd.readUint8());

  @pragma('vm:prefer-inline')
  Map<Object?, Object?> unpackMap() => _unpackMap(_rd.readUint8());

  @pragma('vm:prefer-inline')
  Object? unpackNull() {
    final header = _rd.readUint8();
    if (header != fNil) {
      _throwExpected('null', header);
    }
    return null;
  }

  Object? unpack() {
    if (!hasBytesAvailable) {
      throw const MessagePackFormatException('No more data to unpack');
    }

    final header = _rd.readUint8();

    return switch (header) {
      fNil => null,
      fFalse || fTrue => _unpackBool(header),
      fFloat32 || fFloat64 => _unpackDouble(header),

      <= limitInt8 ||
      >= fNegFixIntPrefix ||
      fUint8 ||
      fUint16 ||
      fUint32 ||
      fUint64 ||
      fInt8 ||
      fInt16 ||
      fInt32 ||
      fInt64 => _unpackInt(header),

      (>= fFixStrPrefix && <= fFixStrEnd) ||
      fStr8 ||
      fStr16 ||
      fStr32 => _unpackString(header),

      (>= fFixArrayPrefix && <= fFixArrayEnd) ||
      fArray16 ||
      fArray32 => _unpackArray(header),

      (>= fFixMapPrefix && <= fFixMapEnd) ||
      fMap16 ||
      fMap32 => _unpackMap(header),

      fBin8 || fBin16 || fBin32 => _unpackBinary(header),

      fFixExt1 ||
      fFixExt2 ||
      fFixExt4 ||
      fFixExt8 ||
      fFixExt16 ||
      fExt8 ||
      fExt16 ||
      fExt32 => _unpackExtension(header),

      fNeverUsed => throw const MessagePackFormatException(
        'Invalid format byte 0xc1 (never used)',
      ),

      _ => throw MessagePackFormatException(
        'Unknown format byte: 0x${header.toRadixString(16).padLeft(2, '0')}',
      ),
    };
  }

  @pragma('vm:prefer-inline')
  int _unpackInt(int header) => switch (header) {
    <= limitInt8 => header,
    >= fNegFixIntPrefix => header - 256,
    fUint8 => _rd.readUint8(),
    fUint16 => _rd.readUint16(),
    fUint32 => _rd.readUint32(),
    fUint64 => _rd.readUint64(),
    fInt8 => _rd.readInt8(),
    fInt16 => _rd.readInt16(),
    fInt32 => _rd.readInt32(),
    fInt64 => _rd.readInt64(),
    _ => _throwExpected('integer', header),
  };

  @pragma('vm:prefer-inline')
  double _unpackDouble(int header) => switch (header) {
    fFloat32 => _rd.readFloat32(),
    fFloat64 => _rd.readFloat64(),
    _ => _throwExpected('float/double', header),
  };

  @pragma('vm:prefer-inline')
  bool _unpackBool(int header) => switch (header) {
    fTrue => true,
    fFalse => false,
    _ => _throwExpected('bool', header),
  };

  @pragma('vm:prefer-inline')
  String _unpackString(int header) {
    final len = switch (header) {
      >= fFixStrPrefix && <= fFixStrEnd => header & fFixStrDataMask,
      fStr8 => _rd.readUint8(),
      fStr16 => _rd.readUint16(),
      fStr32 => _rd.readUint32(),
      _ => _throwExpected('string', header),
    };

    return _rd.readString(len);
  }

  @pragma('vm:prefer-inline')
  Uint8List _unpackBinary(int header) {
    final len = switch (header) {
      fBin8 => _rd.readUint8(),
      fBin16 => _rd.readUint16(),
      fBin32 => _rd.readUint32(),
      _ => _throwExpected('binary', header),
    };

    return _rd.readBytes(len);
  }

  @pragma('vm:prefer-inline')
  List<Object?> _unpackArray(int header) {
    final len = switch (header) {
      >= fFixArrayPrefix && <= fFixArrayEnd => header & fFixCountMask,
      fArray16 => _rd.readUint16(),
      fArray32 => _rd.readUint32(),
      _ => _throwExpected('array', header),
    };

    if (len == 0) {
      return const [];
    }

    final list = List<Object?>.filled(len, null);
    for (var i = 0; i < len; i++) {
      list[i] = unpack();
    }

    return list;
  }

  @pragma('vm:prefer-inline')
  Map<Object?, Object?> _unpackMap(int header) {
    final len = switch (header) {
      >= fFixMapPrefix && <= fFixMapEnd => header & fFixCountMask,
      fMap16 => _rd.readUint16(),
      fMap32 => _rd.readUint32(),
      _ => _throwExpected('map', header),
    };

    if (len == 0) {
      return const {};
    }

    final map = _i.preserveMapOrder
        ? <Object?, Object?>{}
        : HashMap<Object?, Object?>();

    for (var i = 0; i < len; i++) {
      map[unpack()] = unpack();
    }

    return map;
  }

  @pragma('vm:prefer-inline')
  Object? _unpackExtension(int header) {
    final len = switch (header) {
      fFixExt1 => 1,
      fFixExt2 => 2,
      fFixExt4 => 4,
      fFixExt8 => 8,
      fFixExt16 => 16,
      fExt8 => _rd.readUint8(),
      fExt16 => _rd.readUint16(),
      fExt32 => _rd.readUint32(),
      _ => _throwExpected('extension', header),
    };

    final extType = _rd.readInt8();
    if (extType == extTypeTimestamp) {
      return _unpackTimestamp(len);
    }

    return _ext?.call(extType, _rd.readBytes(len));
  }

  @pragma('vm:prefer-inline')
  Never _throwExpected(String expectedType, int actualHeader) {
    throw MessagePackFormatException(
      'Expected $expectedType format, but found byte: '
      '0x${actualHeader.toRadixString(16).padLeft(2, '0')}',
    );
  }

  @pragma('vm:prefer-inline')
  DateTime _unpackTimestamp(int length) {
    switch (length) {
      case 4:
        final seconds = _rd.readUint32();
        return DateTime.fromMillisecondsSinceEpoch(
          seconds * 1000,
          isUtc: true,
        );
      case 8:
        final data64 = _rd.readUint64();
        final nanoSeconds = (data64 >> 34) & 0x3FFFFFFF;
        final seconds = data64 & 0x3FFFFFFFF;
        final microseconds = seconds * 1000000 + nanoSeconds ~/ 1000;
        return DateTime.fromMicrosecondsSinceEpoch(
          microseconds,
          isUtc: true,
        );
      case 12:
        final nanoSeconds = _rd.readUint32();
        final seconds = _rd.readInt64();
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

  List<Object?> unpackAll() {
    final result = <Object?>[];
    while (hasBytesAvailable) {
      result.add(unpack());
    }
    return result;
  }

  /// Releases resources associated with the unpacker.
  ///
  /// Currently a no-op, but provided for symmetry with [Packer.dispose].
  void dispose() {
    // No-op for now
  }
}

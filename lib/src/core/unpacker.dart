/// MessagePack deserializer.
///
/// This library provides the [Unpacker] class, which is a low-level,
/// high-performance
/// MessagePack decoder.
library;

import 'dart:typed_data';

import 'package:pro_binary/pro_binary.dart';

import 'constants.dart';
import 'exception.dart';
import 'grammar.dart';
import 'timestamp.dart';

/// Called by the [Unpacker] when it encounters a MessagePack ext type.
///
/// * [type]: The extension type code (-128..127).
/// * [length]: The byte length of the extension payload.
/// * [unpacker]: The unpacker to read the payload from.
///
/// Should return the decoded Dart object.
typedef DecodeExt = dynamic Function(int type, int length, Unpacker unpacker);

/// Internal unpacker state for the [Unpacker] extension type.
typedef _UnpackerState = ({BinaryReader reader, dynamic decodeExt});

/// Shared empty buffer for default initialization.
final _emptyBuffer = Uint8List(0);

/// A high-performance MessagePack deserializer.
///
/// [Unpacker] is implemented as an `extension type` over a [BinaryReader] from
/// `pro_binary`, providing a zero-overhead wrapper for decoding MessagePack
/// data.
///
/// **Features:**
/// - **Zero-Overhead**: No extra memory or object allocation for the wrapper.
/// - **Efficient Decoding**: Stream-like parsing with minimal branching.
/// - **Buffer Reuse**: Supports [rebind] to switch buffers without
///   re-allocating the reader or unpacker instances.
///
/// Example:
/// ```dart
/// final unpacker = Unpacker(buffer: bytes);
/// final data = unpacker.unpack();
/// ```
extension type Unpacker._(_UnpackerState _st) {
  /// Creates a new [Unpacker] for the given [buffer].
  ///
  /// * [decodeExt]: Optional callback for decoding custom extension types.
  Unpacker({
    required Uint8List buffer,
    DecodeExt? decodeExt,
  }) : _st = (reader: BinaryReader(buffer), decodeExt: decodeExt);

  /// Creates an [Unpacker] with an empty buffer, ready to be [rebind]-ed.
  Unpacker.withEmptyBuffer({
    DecodeExt? decodeExt,
  }) : _st = (
         reader: BinaryReader(_emptyBuffer),
         decodeExt: decodeExt,
       );

  /// The underlying [BinaryReader].
  @pragma('vm:prefer-inline')
  BinaryReader get _rd => _st.reader;

  /// The current read position in the underlying buffer.
  @pragma('vm:prefer-inline')
  int get offset => _rd.offset;

  /// The custom extension decoder callback.
  @pragma('vm:prefer-inline')
  DecodeExt? get _ext => _st.decodeExt as DecodeExt?;

  /// Whether there are more bytes to read in the current buffer.
  @pragma('vm:prefer-inline')
  bool get hasBytesAvailable => _rd.availableBytes > 0;

  /// Reads [length] bytes directly from the underlying buffer.
  @pragma('vm:prefer-inline')
  Uint8List readBytes(int length) => _rd.readBytes(length);

  /// Returns the bytes remaining in the buffer from the current position.
  @pragma('vm:prefer-inline')
  Uint8List get remainingBytes => _rd.readRemainingBytes();

  /// Unpacks the next value as an integer.
  ///
  /// Returns `null` if the value is a MessagePack nil byte.
  @pragma('vm:prefer-inline')
  int? unpackInt() => _readNullable(_unpackInt);

  /// Unpacks the next value as a double (float 32 or float 64).
  ///
  /// Returns `null` if the value is a MessagePack nil byte.
  @pragma('vm:prefer-inline')
  double? unpackDouble() => _readNullable(_unpackDouble);

  /// Unpacks the next value as a boolean.
  ///
  /// Returns `null` if the value is a MessagePack nil byte.
  @pragma('vm:prefer-inline')
  bool? unpackBool() => _readNullable(_unpackBool);

  /// Unpacks the next value as a [String].
  ///
  /// Returns `null` if the value is a MessagePack nil byte.
  @pragma('vm:prefer-inline')
  String? unpackString() => _readNullable(_unpackString);

  /// Unpacks the next value as binary data ([Uint8List]).
  ///
  /// Returns `null` if the value is a MessagePack nil byte.
  @pragma('vm:prefer-inline')
  Uint8List? unpackBinary() => _readNullable(_unpackBinary);

  /// Unpacks the next value as an array ([List]).
  ///
  /// Returns `null` if the value is a MessagePack nil byte.
  @pragma('vm:prefer-inline')
  List<dynamic>? unpackArray() => _readNullable(_unpackArray);

  /// Unpacks the next value as an array of a specific type [T].
  List<T> unpackArrayOf<T>() => unpackArray()!.cast<T>();

  /// Unpacks the next value as a [Map].
  ///
  /// Returns `null` if the value is a MessagePack nil byte.
  @pragma('vm:prefer-inline')
  Map<dynamic, dynamic>? unpackMap() => _readNullable(_unpackMap);

  /// Unpacks the next value as a map with keys of type [K] and values of type
  /// [V].
  ///
  /// Throws if the value is a MessagePack nil byte; for a nullable map use
  /// [unpackMap] and cast yourself.
  Map<K, V> unpackMapOf<K, V>() => unpackMap()!.cast<K, V>();

  /// Reads only the next array header and returns its element count.
  ///
  /// The caller must then read exactly that many values with the typed unpack
  /// methods. This is the low-level dual of [unpackArray] for decoding an array
  /// element-by-element without materializing a [List]. It does not handle
  /// `nil` — a nullable array is the caller's concern.
  ///
  /// Throws [MessagePackFormatException] if the next header is not an array.
  @pragma('vm:prefer-inline')
  int unpackArrayLength() => _arrayLength(_rd.readUint8());

  /// Reads only the next map header and returns its entry count.
  ///
  /// The caller must then read exactly that many key/value pairs with the typed
  /// unpack methods. This is the low-level dual of [unpackMap] for decoding a
  /// map entry-by-entry without materializing a [Map]. It does not handle
  /// `nil` — a nullable map is the caller's concern.
  ///
  /// Throws [MessagePackFormatException] if the next header is not a map.
  @pragma('vm:prefer-inline')
  int unpackMapLength() => _mapLength(_rd.readUint8());

  /// Unpacks the next value as a MessagePack timestamp extension ([DateTime]).
  ///
  /// Returns `null` if the value is a MessagePack nil byte.
  @pragma('vm:prefer-inline')
  DateTime? unpackTimestamp() => _readNullable(_unpackExt) as DateTime?;

  /// Unpacks the next value as a custom extension type [T].
  ///
  /// Returns `null` if the value is a MessagePack nil byte.
  @pragma('vm:prefer-inline')
  T unpackExt<T>() => _readNullable(_unpackExt) as T;

  /// Unpacks the next value as the expected type [T].
  ///
  /// Throws a [TypeError] if the unpacked value cannot be cast to [T].
  @pragma('vm:prefer-inline')
  T unpackAs<T>() => unpack() as T;

  /// Unpacks the next object from the buffer, automatically detecting its type.
  ///
  /// This is the primary method for decoding any MessagePack-encoded value.
  ///
  /// Throws [MessagePackFormatException] if the buffer is empty or contains
  /// invalid MessagePack data.
  /// Throws [RangeError] if the buffer is exhausted prematurely mid-value.
  @pragma('vm:prefer-inline')
  dynamic unpack() {
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
      fExt32 => _unpackExt(header),

      fNeverUsed => throw const MessagePackFormatException(
        'Invalid format byte 0xc1 (never used)',
      ),

      _ => throw MessagePackFormatException(
        'Unknown format byte: 0x${header.toRadixString(16).padLeft(2, '0')}',
      ),
    };
  }

  /// Advances past exactly one complete value of any type (scalar, string,
  /// binary, array, map, ext, nil), leaving the reader positioned at the next
  /// value. For an array or map it skips the header and all nested elements
  /// recursively.
  ///
  /// This is the buffered counterpart of [unpack] — it walks the same shared
  /// wire-format grammar but advances the offset instead of materializing a
  /// value. Use it to drop the value under an unrecognised key.
  ///
  /// Throws [MessagePackFormatException] on a reserved (`0xc1`) or unknown
  /// header byte, and [RangeError] if the buffer is exhausted mid-value.
  void skip() {
    final header = _rd.readUint8();

    switch (mpShapes[header]) {
      case MpShape.single:
        break;
      case MpShape.fixed:
        _rd.skip(mpFixedSkip[header]);
      case MpShape.fixExt:
        _rd.skip(1 + mpFixedSkip[header]); // type byte + data
      case MpShape.fixStr:
        _rd.skip(header & fFixStrDataMask);
      case MpShape.strBin8:
        _rd.skip(_rd.readUint8());
      case MpShape.strBin16:
        _rd.skip(_rd.readUint16());
      case MpShape.strBin32:
        _rd.skip(_rd.readUint32());
      case MpShape.fixArray:
        _skipValues(header & fFixCountMask);
      case MpShape.array16:
        _skipValues(_rd.readUint16());
      case MpShape.array32:
        _skipValues(_rd.readUint32());
      case MpShape.fixMap:
        _skipValues((header & fFixCountMask) * 2);
      case MpShape.map16:
        _skipValues(_rd.readUint16() * 2);
      case MpShape.map32:
        _skipValues(_rd.readUint32() * 2);
      case MpShape.ext8:
        _rd.skip(_rd.readUint8() + 1); // data + type byte
      case MpShape.ext16:
        _rd.skip(_rd.readUint16() + 1);
      case MpShape.ext32:
        _rd.skip(_rd.readUint32() + 1);
      case MpShape.neverUsed:
        throw const MessagePackFormatException(
          'Invalid format byte 0xc1 (never used)',
        );
      case MpShape.unknown:
        throw MessagePackFormatException(
          'Unknown format byte: 0x${header.toRadixString(16).padLeft(2, '0')}',
        );
    }
  }

  /// Skips [count] consecutive values (array elements or map keys+values).
  void _skipValues(int count) {
    for (var i = 0; i < count; i++) {
      skip();
    }
  }

  /// Internal: Reads the next header byte. If it is `nil`, returns `null`.
  /// Otherwise, calls the [parser] with the header byte.
  @pragma('vm:prefer-inline')
  T? _readNullable<T>(T Function(int) parser) {
    final header = _rd.readUint8();
    return header == fNil ? null : parser(header);
  }

  /// Internal: Decodes an integer based on its header.
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

  /// Internal: Decodes a float or double based on its header.
  @pragma('vm:prefer-inline')
  double _unpackDouble(int header) => switch (header) {
    fFloat32 => _rd.readFloat32(),
    fFloat64 => _rd.readFloat64(),
    _ => _throwExpected('float/double', header),
  };

  /// Internal: Decodes a boolean based on its header.
  @pragma('vm:prefer-inline')
  bool _unpackBool(int header) => switch (header) {
    fTrue => true,
    fFalse => false,
    _ => _throwExpected('bool', header),
  };

  /// Internal: Decodes a string based on its header.
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

  /// Internal: Decodes binary data based on its header.
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

  /// Internal: Reads an array header's element count.
  @pragma('vm:prefer-inline')
  int _arrayLength(int header) => switch (header) {
    >= fFixArrayPrefix && <= fFixArrayEnd => header & fFixCountMask,
    fArray16 => _rd.readUint16(),
    fArray32 => _rd.readUint32(),
    _ => _throwExpected('array', header),
  };

  /// Internal: Reads a map header's entry count.
  @pragma('vm:prefer-inline')
  int _mapLength(int header) => switch (header) {
    >= fFixMapPrefix && <= fFixMapEnd => header & fFixCountMask,
    fMap16 => _rd.readUint16(),
    fMap32 => _rd.readUint32(),
    _ => _throwExpected('map', header),
  };

  /// Internal: Decodes an array based on its header.
  @pragma('vm:prefer-inline')
  List<dynamic> _unpackArray(int header) {
    final len = _arrayLength(header);

    if (len == 0) {
      return const [];
    }

    final list = List<dynamic>.filled(len, null);
    for (var i = 0; i < len; i++) {
      list[i] = unpack();
    }

    return list;
  }

  /// Internal: Decodes a map based on its header.
  @pragma('vm:prefer-inline')
  Map<dynamic, dynamic> _unpackMap(int header) {
    final len = _mapLength(header);

    if (len == 0) {
      return const {};
    }

    final map = <dynamic, dynamic>{};
    for (var i = 0; i < len; i++) {
      final k = unpack();
      final v = unpack();
      map[k] = v;
    }

    return map;
  }

  /// Internal: Decodes an extension payload of a given length.
  @pragma('vm:prefer-inline')
  dynamic _unpackExt(int header) {
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

    final expectedEnd = _rd.offset + len;
    final result = _ext?.call(extType, len, this);

    if (_rd.offset != expectedEnd) {
      _rd.seek(expectedEnd);
    }

    return result;
  }

  /// Internal: Helper to throw a [MessagePackFormatException] when an
  /// unexpected
  /// byte is encountered.
  @pragma('vm:prefer-inline')
  Never _throwExpected(String expectedType, int actualHeader) {
    throw MessagePackFormatException(
      'Expected $expectedType format, but found byte: '
      '0x${actualHeader.toRadixString(16).padLeft(2, '0')}',
    );
  }

  /// Internal: Decodes a MessagePack timestamp extension via the
  /// [MessagePackTimestamp] codec.
  @pragma('vm:prefer-inline')
  DateTime _unpackTimestamp(int length) =>
      MessagePackTimestamp.decode(_rd, length);

  /// Rebinds the underlying [BinaryReader] to a new [buffer] without creating
  /// a new [Unpacker] instance.
  ///
  /// This is an advanced optimization to minimize object allocations during
  /// repetitive decoding tasks or nested decoding (e.g., in extension groups).
  @pragma('vm:prefer-inline')
  void rebind(Uint8List buffer) => _rd.rebind(buffer);
}

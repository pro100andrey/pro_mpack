import 'dart:convert';
import 'dart:typed_data';

import 'package:pro_binary/pro_binary.dart';

import 'constants.dart';
import 'error.dart';

/// A mixin that provides functionality for encoding custom extension types.
///
/// This mixin is intended to be implemented by classes that handle the encoding
/// of custom extension types in MessagePack format. The implementing class must
/// provide the implementations for the `extTypeForObject` and `encodeObject`
///  methods.
mixin ExtEncoder {
  /// Returns the extension type for a given [object].
  ///
  /// This method determines the custom extension type integer that represents
  /// the given [object]. If the object cannot be encoded as an extension type,
  /// the method returns `null`.
  ///
  /// [object] is the object to be encoded as an extension type.
  ///
  /// Returns an integer representing the extension type, or `null` if the
  /// object cannot be encoded.
  int? extTypeForObject(dynamic object);

  /// Encodes a given [object] into a Uint8List.
  ///
  /// This method serializes the given [object] into a binary format represented
  /// by a `Uint8List`. It should be used for objects that can be encoded as
  /// custom extension types.
  ///
  /// [object] is the object to be encoded.
  ///
  /// Returns a `Uint8List` representing the encoded object.
  ///
  /// Throws an [MessagePackError] if the object cannot be encoded.
  Uint8List encodeObject(dynamic object);
}

/// A class representing a custom floating-point number.
class Float {
  Float(this.value);

  final double value;

  @override
  String toString() => 'Float($value)';
}

/// A class responsible for serializing various data types into MessagePack
/// format.
class Serializer {
  /// Creates a Serializer with an optional [extEncoder].
  ///
  /// The [extEncoder] parameter is used for encoding custom extension types.
  /// If provided, the serializer will use the encoder to serialize custom
  /// extension types. Otherwise, custom extensions will not be encoded.
  /// The [initialBufferSize] parameter specifies the initial size of the buffer
  /// used for encoding. This value is used to optimize the encoding process by
  /// reducing the number of reallocations. The default value is `64`.
  Serializer({
    ExtEncoder? extEncoder,
    int initialBufferSize = 64,
  }) : _extEncoder = extEncoder {
    _writer = BinaryWriter(initialBufferSize: initialBufferSize);
  }

  late final BinaryWriter _writer;
  final ExtEncoder? _extEncoder;

  /// Encodes a given [value] into MessagePack format.
  ///
  /// The [value] can be of various types such as int, double, String, List,
  /// Map, or null.
  void encode(dynamic value) {
    switch (value) {
      case null:
        _writer.writeUint8(formatNil);
      case bool():
        _writer.writeUint8(value ? formatTrue : formatFalse);
      case int() when value < 0:
        _writeNegativeInt(value);
      case int():
        _writePositiveInt(value);
      case Float():
        _writeFloat(value);
      case double():
        _writeDouble(value);
      case String():
        _writeString(value);
      case Uint8List():
        _writeBinary(value);
      case Iterable():
        _writeIterable(value);
      case ByteData():
        _writeBinary(
          value.buffer.asUint8List(
            value.offsetInBytes,
            value.lengthInBytes,
          ),
        );
      case Map():
        _writeMap(value);
      case DateTime():
        _writeTimestamp(value);
      case _ when _extEncoder != null && _writeExt(value):
        return;
      case _:
        throw MessagePackError("Don't know how to serialize $value");
    }
  }

  /// Returns the serialized bytes as a Uint8List.
  /// After calling this method, the serializer is reset and can be used again.
  Uint8List takeBytes() => _writer.takeBytes();

  void _writeNegativeInt(int value) {
    switch (value) {
      case >= limitNegativeInt5:
        _writer.writeInt8(value); // negative fixint
      case >= limitNegativeInt8:
        _writer
          ..writeUint8(formatInt8)
          ..writeInt8(value);
      case >= limitNegativeInt16:
        _writer
          ..writeUint8(formatInt16)
          ..writeInt16(value);
      case >= limitNegativeInt32:
        _writer
          ..writeUint8(formatInt32)
          ..writeInt32(value);
      default:
        _writer
          ..writeUint8(formatInt64)
          ..writeInt64(value);
    }
  }

  void _writePositiveInt(int value) {
    switch (value) {
      case <= limitInt8:
        _writer.writeUint8(value); // positive fixint
      case <= limitUint8:
        _writer
          ..writeUint8(formatUint8)
          ..writeUint8(value);
      case <= limitUint16:
        _writer
          ..writeUint8(formatUint16)
          ..writeUint16(value);
      case <= limitUint32:
        _writer
          ..writeUint8(formatUint32)
          ..writeUint32(value);
      default:
        _writer
          ..writeUint8(formatUint64)
          ..writeUint64(value);
    }
  }

  void _writeFloat(Float value) {
    _writer
      ..writeUint8(formatFloat32)
      ..writeFloat32(value.value);
  }

  void _writeDouble(double value) {
    _writer
      ..writeUint8(formatFloat64)
      ..writeFloat64(value);
  }

  void _writeString(String value) {
    final encoded = const Utf8Encoder().convert(value);
    final length = encoded.length;

    switch (length) {
      case <= 31:
        _writer.writeUint8(formatFixStrPrefix | length);
      case <= limitUint8:
        _writer
          ..writeUint8(formatStr8)
          ..writeUint8(length);
      case <= limitUint16:
        _writer
          ..writeUint8(formatStr16)
          ..writeUint16(length);
      case <= limitUint32:
        _writer
          ..writeUint8(formatStr32)
          ..writeUint32(length);
      default:
        throw MessagePackError(
          'String is too long to be serialized with messagePack.',
        );
    }

    _writer.writeBytes(encoded);
  }

  void _writeBinary(Uint8List buffer) {
    final length = buffer.length;

    switch (length) {
      case <= limitUint8:
        _writer
          ..writeUint8(formatBin8)
          ..writeUint8(length);
      case <= limitUint16:
        _writer
          ..writeUint8(formatBin16)
          ..writeUint16(length);
      case <= limitUint32:
        _writer
          ..writeUint8(formatBin32)
          ..writeUint32(length);
      default:
        throw MessagePackError(
          'Data is too long to be serialized with messagePack.',
        );
    }

    _writer.writeBytes(buffer);
  }

  void _writeIterable(Iterable iterable) {
    final length = iterable.length;

    switch (length) {
      case <= 15:
        _writer.writeUint8(formatFixArrayPrefix | length);
      case <= limitUint16:
        _writer
          ..writeUint8(formatArray16)
          ..writeUint16(length);
      case <= limitUint32:
        _writer
          ..writeUint8(formatArray32)
          ..writeUint32(length);
      default:
        throw MessagePackError(
          'Array is too big to be serialized with messagePack',
        );
    }

    iterable.forEach(encode);
  }

  void _writeMap(Map dictionary) {
    final length = dictionary.length;

    switch (length) {
      case <= 15:
        _writer.writeUint8(formatFixMapPrefix | length);
      case <= limitUint16:
        _writer
          ..writeUint8(formatMap16)
          ..writeUint16(length);
      case <= limitUint32:
        _writer
          ..writeUint8(formatMap32)
          ..writeUint32(length);
      default:
        throw MessagePackError(
          'Map is too big to be serialized with messagePack',
        );
    }

    for (final item in dictionary.entries) {
      encode(item.key);
      encode(item.value);
    }
  }

  void _writeTimestamp(DateTime value) {
    final utc = value.toUtc();
    final seconds = utc.millisecondsSinceEpoch ~/ 1000;
    final nanoseconds = (utc.microsecondsSinceEpoch % 1000000) * 1000;

    if ((seconds >> 34) == 0) {
      // 32-bit (secs) or 64-bit (30-bit nsec | 34-bit secs)
      final data64 = (nanoseconds << 34) | seconds;

      if ((data64 & 0xffffffff00000000) == 0) {
        // Can fit in 32 bits? only if nanoseconds is 0?
        if (nanoseconds == 0 && seconds >= 0 && seconds <= limitUint32) {
          _writer
            ..writeUint8(formatFixExt4)
            ..writeInt8(extTypeTimestamp)
            ..writeUint32(seconds);
          return;
        }
      }

      // Timestamp 64
      _writer
        ..writeUint8(formatFixExt8)
        ..writeInt8(extTypeTimestamp)
        ..writeUint64(data64);
    } else {
      // Timestamp 96
      _writer
        ..writeUint8(formatExt8)
        ..writeUint8(12) // length
        ..writeInt8(extTypeTimestamp)
        ..writeUint32(nanoseconds)
        ..writeInt64(seconds);
    }
  }

  bool _writeExt(dynamic object) {
    final type = _extEncoder?.extTypeForObject(object);

    if (type != null) {
      final encoded = _extEncoder?.encodeObject(object);

      if (encoded == null) {
        throw MessagePackError(
          'Unable to encode object. No Encoder specified.',
        );
      }

      final length = encoded.length;

      switch (length) {
        case 1:
          _writer.writeUint8(formatFixExt1);
        case 2:
          _writer.writeUint8(formatFixExt2);
        case 4:
          _writer.writeUint8(formatFixExt4);
        case 8:
          _writer.writeUint8(formatFixExt8);
        case 16:
          _writer.writeUint8(formatFixExt16);
        case <= limitUint8:
          _writer
            ..writeUint8(formatExt8) // ext8
            ..writeUint8(length);
        case <= limitUint16:
          _writer
            ..writeUint8(formatExt16) // ext16
            ..writeUint16(length);
        case <= limitUint32:
          _writer
            ..writeUint8(formatExt32) // ext32
            ..writeUint32(length);
        case _:
          throw MessagePackError('Size must be at most $limitUint32');
      }

      if (type < -128 || type > 127) {
        throw MessagePackError('Type must be in the range of -128 to 127');
      }

      _writer
        ..writeInt8(type)
        ..writeBytes(encoded);

      return true;
    }

    return false;
  }
}

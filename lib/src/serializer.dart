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
  int? extTypeForObject(Object? object);

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
  Uint8List encodeObject(Object? object);
}

/// A class representing a 32-bit floating-point number.
///
/// By default, Dart's `double` type is serialized as a 64-bit float
/// (float64) in MessagePack. Use [Float] to explicitly serialize a value
/// as a 32-bit float (float32), which can save space when full 64-bit
/// precision is not needed.
///
/// Example:
/// ```dart
/// final data = serialize({
///   'precise': 3.14159265359, // Serialized as float64
///   'compact': Float(3.14),   // Serialized as float32
/// });
/// ```
class Float {
  /// Creates a [Float] with the specified [value].
  Float(this.value);

  final double value;

  @override
  String toString() => 'Float($value)';
}

/// A class responsible for serializing various data types into MessagePack
/// format.
///
/// The [Serializer] class provides a low-level interface for encoding Dart
/// objects into the MessagePack binary format. It maintains an internal
/// buffer that grows as needed during serialization.
///
/// ## Supported Types
///
/// - Primitives: `null`, `bool`, `int`, `double`
/// - Collections: `List`, `Map`, `Iterable`
/// - Binary data: `Uint8List`, `ByteData`
/// - Text: `String` (UTF-8 encoded)
/// - Special: `DateTime` (as timestamp extension), [Float] (32-bit float)
/// - Custom extension types via [ExtEncoder]
///
/// ## Usage
///
/// For most use cases, prefer the high-level `serialize()` function. Use
/// [Serializer] directly when you need more control or are encoding
/// multiple values:
///
/// ```dart
/// final serializer = Serializer();
/// serializer.encode(123);
/// serializer.encode('hello');
/// final bytes = serializer.takeBytes();
/// ```
class Serializer {
  /// Creates a [Serializer] with an optional [extEncoder] and
  /// [initialBufferSize].
  ///
  /// [extEncoder]: Optional encoder for custom extension types. When
  /// provided, objects that match custom types will be encoded using this
  /// encoder.
  ///
  /// [initialBufferSize]: The initial capacity of the internal buffer in
  /// bytes. The buffer will grow automatically as needed, but setting an
  /// appropriate initial size can improve performance by reducing
  /// allocations. Default is `1024`. Consider using larger values (e.g.,
  /// 8192 or 16384) when encoding large objects.
  Serializer({
    ExtEncoder? extEncoder,
    int initialBufferSize = 1024,
  }) : _extEncoder = extEncoder {
    _writer = BinaryWriter(initialBufferSize: initialBufferSize);
  }

  late final BinaryWriter _writer;
  final ExtEncoder? _extEncoder;

  /// Encodes a given [value] into MessagePack format.
  ///
  /// This method determines the appropriate MessagePack encoding based on
  /// the runtime type of [value] and writes it to the internal buffer.
  ///
  /// [value]: The object to encode. Can be:
  /// - `null` → nil format (0xc0)
  /// - `bool` → true (0xc3) or false (0xc2)
  /// - `int` → fixint, or int8/16/32/64 based on value range
  /// - [Float] → float32
  /// - `double` → float64
  /// - `String` → fixstr, str8/16/32 based on length
  /// - `Uint8List` or `ByteData` → bin8/16/32
  /// - `Iterable` → fixarray or array16/32
  /// - `Map` → fixmap or map16/32
  /// - `DateTime` → timestamp extension (-1)
  /// - Custom types via [ExtEncoder]
  ///
  /// Throws [MessagePackError] if the value cannot be serialized or if
  /// it's too large for the MessagePack format limits.
  void encode(Object? value) {
    switch (value) {
      case null:
        writeNull();
      case bool():
        writeBool(value);
      case int():
        writeInt(value);
      case Float():
        writeFloat(value);
      case double():
        writeDouble(value);
      case String():
        writeString(value);
      case Uint8List():
        writeBinary(value);
      case Iterable():
        writeIterable(value);
      case ByteData():
        writeBinary(
          value.buffer.asUint8List(
            value.offsetInBytes,
            value.lengthInBytes,
          ),
        );
      case Map():
        writeMap(value);
      case DateTime():
        writeTimestamp(value);
      case _ when _extEncoder != null && writeExt(value):
        return;
      case _:
        throw MessagePackError("Don't know how to serialize $value");
    }
  }

  /// Returns the serialized bytes as a [Uint8List] and resets the internal
  /// buffer.
  ///
  /// This method extracts all encoded data from the internal buffer and
  /// returns it as a [Uint8List]. After calling this method, the
  /// serializer's buffer is cleared and ready for reuse.
  ///
  /// Example:
  /// ```dart
  /// final serializer = Serializer();
  /// serializer.encode({'a': 1});
  /// final bytes1 = serializer.takeBytes();
  ///
  /// serializer.encode({'b': 2}); // Reuse the serializer
  /// final bytes2 = serializer.takeBytes();
  /// ```
  ///
  /// Returns a [Uint8List] containing all MessagePack-encoded data.
  Uint8List takeBytes() => _writer.takeBytes();

  @pragma('vm:prefer-inline')
  @pragma('dart2js:tryInline')
  //
  // ignore: avoid_positional_boolean_parameters
  void writeBool(bool value) {
    _writer.writeUint8(value ? formatTrue : formatFalse);
  }

  @pragma('vm:prefer-inline')
  @pragma('dart2js:tryInline')
  void writeNull() {
    _writer.writeUint8(formatNil);
  }

  @pragma('vm:prefer-inline')
  @pragma('dart2js:tryInline')
  void writeInt(int value) {
    if (value >= 0) {
      writePositiveInt(value);
    } else {
      writeNegativeInt(value);
    }
  }

  @pragma('vm:prefer-inline')
  @pragma('dart2js:tryInline')
  void writeNegativeInt(int value) {
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

  @pragma('vm:prefer-inline')
  @pragma('dart2js:tryInline')
  void writePositiveInt(int value) {
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

  @pragma('vm:prefer-inline')
  @pragma('dart2js:tryInline')
  void writeFloat(Float value) {
    _writer
      ..writeUint8(formatFloat32)
      ..writeFloat32(value.value);
  }

  @pragma('vm:prefer-inline')
  @pragma('dart2js:tryInline')
  void writeDouble(double value) {
    _writer
      ..writeUint8(formatFloat64)
      ..writeFloat64(value);
  }

  @pragma('vm:prefer-inline')
  @pragma('dart2js:tryInline')
  void writeString(String value) {
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

  @pragma('vm:prefer-inline')
  @pragma('dart2js:tryInline')
  void writeBinary(Uint8List buffer) {
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

  @pragma('vm:prefer-inline')
  @pragma('dart2js:tryInline')
  void writeIterable(Iterable iterable) {
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

    // Optimize for List to avoid iterator overhead
    if (iterable is List) {
      for (var i = 0; i < length; i++) {
        encode(iterable[i]);
      }
    } else {
      // no allocate lambda for each item
      // ignore: prefer_foreach
      for (final item in iterable) {
        encode(item);
      }
    }
  }

  @pragma('vm:prefer-inline')
  @pragma('dart2js:tryInline')
  void writeMap(Map dictionary) {
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

    dictionary.forEach((key, value) {
      encode(key);
      encode(value);
    });
  }

  @pragma('vm:prefer-inline')
  @pragma('dart2js:tryInline')
  void writeTimestamp(DateTime value) {
    final micro = (value.isUtc ? value : value.toUtc()).microsecondsSinceEpoch;
    final sec = (micro / 1000000).floor();
    final nano = ((micro % 1000000 + 1000000) % 1000000) * 1000;

    if ((sec >> 34) == 0) {
      // 32-bit (secs) or 64-bit (30-bit nsec | 34-bit secs)
      final data64 = (nano << 34) | sec;

      // Timestamp 32
      // 1970 ... 2106 and no nanoseconds
      if (nano == 0 && sec >= 0 && sec <= limitUint32) {
        _writer
          ..writeUint8(formatFixExt4)
          ..writeInt8(extTypeTimestamp)
          ..writeUint32(sec);
        return;
      }

      // Timestamp 64
      // 1970 ... ~2514 with nanoseconds
      _writer
        ..writeUint8(formatFixExt8)
        ..writeInt8(extTypeTimestamp)
        ..writeInt64(data64);
    } else {
      // Timestamp 96
      // Before 1970 or after ~2514
      _writer
        ..writeUint8(formatExt8)
        ..writeUint8(12) // length
        ..writeInt8(extTypeTimestamp)
        ..writeUint32(nano)
        ..writeInt64(sec);
    }
  }

  @pragma('vm:prefer-inline')
  @pragma('dart2js:tryInline')
  bool writeExt(Object? object) {
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

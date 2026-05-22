/// Components for MessagePack serialization.
library;

import 'dart:typed_data';

import 'package:pro_binary/pro_binary.dart';

import 'constants.dart';
import 'exception.dart';

/// A mixin that defines the interface for encoding custom extension types.
///
/// Classes that want to support custom MessagePack extensions should implement
/// this mixin. It provides methods to determine if an object can be encoded
/// as a custom extension and to perform the actual encoding.
abstract mixin class ExtEncoder {
  /// Returns the extension type code for a given [object].
  ///
  /// The type code must be an integer between -128 and 127.
  /// Type -1 is reserved for the built-in [DateTime] (timestamp) extension.
  ///
  /// Returns `null` if the object cannot be encoded as an extension type.
  int? extTypeForObject(Object? object);

  /// Encodes [object] into its binary representation.
  ///
  /// This method is called only if [extTypeForObject] returned a non-null value
  /// for the same object.
  ///
  /// Returns a [Uint8List] containing the encoded bytes.
  ///
  /// Throws a [MessagePackException] if encoding fails.
  Uint8List encodeObject(Object? object);
}

/// A wrapper for explicitly serializing a [double] as a 32-bit float.
///
/// In MessagePack, Dart's `double` type (64-bit) is serialized as `float 64`
/// by default. Use [Float] to force serialization as `float 32`, saving 4 bytes
/// when full 64-bit precision is not required.
///
/// Example:
/// ```dart
/// final data = serialize(Float(3.14)); // Encoded as float 32
/// ```
class Float {
  /// Creates a [Float] wrapper for the given [value].
  Float(this.value);

  /// The underlying double value.
  final double value;

  @override
  String toString() => 'Float($value)';
}

/// A class for encoding Dart objects into MessagePack binary format.
///
/// [Serializer] provides a stateful way to encode multiple values into a
/// single buffer. It manages an internal, growing buffer for performance.
///
/// Example:
/// ```dart
/// final serializer = Serializer();
/// serializer.encode(true);
/// serializer.encode(42);
/// final bytes = serializer.takeBytes();
/// ```
class Serializer {
  /// Creates a [Serializer] instance.
  ///
  /// [extEncoder] provides support for custom extension types.
  /// [initialBufferSize] sets the initial capacity of the internal buffer.
  /// The buffer grows automatically if needed.
  Serializer({
    ExtEncoder? extEncoder,
    int initialBufferSize = 1024,
  }) : _extEncoder = extEncoder {
    _writer = BinaryWriterPool.acquire(initialBufferSize);
  }

  late final BinaryWriter _writer;
  final ExtEncoder? _extEncoder;

  /// Encodes [value] into MessagePack format and writes it to the buffer.
  ///
  /// Supports all standard MessagePack types:
  /// - `null` -> nil
  /// - `bool` -> true/false
  /// - `int` -> positive/negative fixint, uint8-64, int8-64
  /// - `double` -> float 64
  /// - [Float] -> float 32
  /// - `String` -> fixstr, str8-32
  /// - `Uint8List`/`ByteData` -> bin8-32
  /// - `Iterable` -> fixarray, array16-32
  /// - `Map` -> fixmap, map16-32
  /// - `DateTime` -> timestamp extension (-1)
  /// - Custom types via [ExtEncoder]
  ///
  /// Throws a [MessagePackException] if the value type is not supported or
  /// if collection sizes exceed MessagePack limits.
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
        throw MessagePackUnsupportedTypeException(
          value.runtimeType,
          "Don't know how to serialize type ${value.runtimeType}",
          'Register an ExtEncoder for this type or'
              ' use a standard supported type.',
        );
    }
  }

  @pragma('vm:prefer-inline')
  //
  // ignore: avoid_positional_boolean_parameters
  void writeBool(bool value) {
    _writer.writeUint8(value ? fTrue : fFalse);
  }

  @pragma('vm:prefer-inline')
  void writeNull() {
    _writer.writeUint8(fNil);
  }

  @pragma('vm:prefer-inline')
  void writeInt(int value) {
    value >= 0 ? writePositiveInt(value) : writeNegativeInt(value);
  }

  @pragma('vm:prefer-inline')
  void writeNegativeInt(int value) {
    switch (value) {
      case >= limitNegFixInt:
        _writer.writeInt8(value); // one-byte negative fixint: 111xxxxx
      case >= limitNegInt8:
        _writer
          ..writeUint8(fInt8)
          ..writeInt8(value);
      case >= limitNegInt16:
        _writer
          ..writeUint8(fInt16)
          ..writeInt16(value);
      case >= limitNegInt32:
        _writer
          ..writeUint8(fInt32)
          ..writeInt32(value);
      default:
        _writer
          ..writeUint8(fInt64)
          ..writeInt64(value);
    }
  }

  @pragma('vm:prefer-inline')
  void writePositiveInt(int value) {
    switch (value) {
      case <= limitInt8:
        _writer.writeUint8(value); // positive fixint
      case <= limitUint8:
        _writer
          ..writeUint8(fUint8)
          ..writeUint8(value);
      case <= limitUint16:
        _writer
          ..writeUint8(fUint16)
          ..writeUint16(value);
      case <= limitUint32:
        _writer
          ..writeUint8(fUint32)
          ..writeUint32(value);
      default:
        _writer
          ..writeUint8(fUint64)
          ..writeUint64(value);
    }
  }

  @pragma('vm:prefer-inline')
  void writeFloat(Float value) {
    _writer
      ..writeUint8(fFloat32)
      ..writeFloat32(value.value);
  }

  @pragma('vm:prefer-inline')
  void writeDouble(double value) {
    _writer
      ..writeUint8(fFloat64)
      ..writeFloat64(value);
  }

  @pragma('vm:prefer-inline')
  void writeString(String value) {
    final length = getUtf8Length(value);

    switch (length) {
      case <= 31:
        _writer.writeUint8(fFixStrPrefix | length);
      case <= limitUint8:
        _writer
          ..writeUint8(fStr8)
          ..writeUint8(length);
      case <= limitUint16:
        _writer
          ..writeUint8(fStr16)
          ..writeUint16(length);
      case <= limitUint32:
        _writer
          ..writeUint8(fStr32)
          ..writeUint32(length);
      default:
        throw const MessagePackSizeException(
          'String is too long to be serialized with MessagePack.',
          'Ensure string byte length does not exceed 4,294,967,295 bytes.',
        );
    }

    _writer.writeString(value);
  }

  @pragma('vm:prefer-inline')
  void writeBinary(Uint8List bytes) {
    final length = bytes.length;

    switch (length) {
      case <= limitUint8:
        _writer
          ..writeUint8(fBin8)
          ..writeUint8(length);
      case <= limitUint16:
        _writer
          ..writeUint8(fBin16)
          ..writeUint16(length);
      case <= limitUint32:
        _writer
          ..writeUint8(fBin32)
          ..writeUint32(length);
      default:
        throw const MessagePackSizeException(
          'Binary data is too long to be serialized with MessagePack.',
          'Ensure Uint8List size does not exceed 4,294,967,295 bytes.',
        );
    }

    _writer.writeBytes(bytes);
  }

  @pragma('vm:prefer-inline')
  void writeIterable(Iterable<dynamic> iterable) {
    final length = iterable.length;

    switch (length) {
      case <= 15:
        _writer.writeUint8(fFixArrayPrefix | length);
      case <= limitUint16:
        _writer
          ..writeUint8(fArray16)
          ..writeUint16(length);
      case <= limitUint32:
        _writer
          ..writeUint8(fArray32)
          ..writeUint32(length);
      default:
        throw const MessagePackSizeException(
          'Array is too big to be serialized with MessagePack.',
          'Ensure the Iterable has no more than 4,294,967,295 elements.',
        );
    }

    // Optimize for List to avoid iterator overhead
    if (iterable is List) {
      for (var i = 0; i < length; i++) {
        encode(iterable[i]);
      }
    } else {
      for (final item in iterable) {
        encode(item);
      }
    }
  }

  @pragma('vm:prefer-inline')
  void writeMap(Map<dynamic, dynamic> dictionary) {
    final length = dictionary.length;

    switch (length) {
      case <= 15:
        _writer.writeUint8(fFixMapPrefix | length);
      case <= limitUint16:
        _writer
          ..writeUint8(fMap16)
          ..writeUint16(length);
      case <= limitUint32:
        _writer
          ..writeUint8(fMap32)
          ..writeUint32(length);
      default:
        throw const MessagePackSizeException(
          'Map is too big to be serialized with MessagePack.',
          'Ensure the Map has no more than 4,294,967,295 key-value pairs.',
        );
    }

    for (final entry in dictionary.entries) {
      encode(entry.key);
      encode(entry.value);
    }
  }

  @pragma('vm:prefer-inline')
  bool writeExt(Object? object, [int? resolvedType]) {
    final type = resolvedType ?? _extEncoder?.extTypeForObject(object);

    if (type != null) {
      if (type < -128 || type > 127) {
        throw const MessagePackConfigurationException(
          'Type must be in the range of -128 to 127.',
          'Ensure your custom extension ID is between -128 and 127.',
        );
      }

      final encoded = _extEncoder?.encodeObject(object);

      if (encoded == null) {
        throw MessagePackConfigurationException(
          'Unable to encode object. No Encoder specified.',
          'Check your ExtEncoder implementation for $object.',
        );
      }

      final length = encoded.length;

      switch (length) {
        case 1:
          _writer.writeUint8(fFixExt1);
        case 2:
          _writer.writeUint8(fFixExt2);
        case 4:
          _writer.writeUint8(fFixExt4);
        case 8:
          _writer.writeUint8(fFixExt8);
        case 16:
          _writer.writeUint8(fFixExt16);
        case <= limitUint8:
          _writer
            ..writeUint8(fExt8) // ext8
            ..writeUint8(length);
        case <= limitUint16:
          _writer
            ..writeUint8(fExt16) // ext16
            ..writeUint16(length);
        case <= limitUint32:
          _writer
            ..writeUint8(fExt32) // ext32
            ..writeUint32(length);
        case _:
          throw const MessagePackSizeException(
            'Extension payload is too large.',
            'Ensure the encoded extension data size does not '
                'exceed 4,294,967,295 bytes.',
          );
      }

      _writer
        ..writeInt8(type)
        ..writeBytes(encoded);

      return true;
    }

    return false;
  }

  @pragma('vm:prefer-inline')
  void writeTimestamp(DateTime value) {
    final micro = (value.isUtc ? value : value.toUtc()).microsecondsSinceEpoch;
    const million = 1_000_000;
    final sec = (micro / million).floor();
    final nano = ((micro % million + million) % million) * 1_000;

    if ((sec >> 34) == 0) {
      // 32-bit (secs) or 64-bit (30-bit nsec | 34-bit secs)
      final data64 = (nano << 34) | sec;
      // Timestamp 32
      // 1970 ... 2106 and no nanoseconds
      if (nano == 0 && sec >= 0 && sec <= limitUint32) {
        _writer
          ..writeUint8(fFixExt4)
          ..writeInt8(extTypeTimestamp)
          ..writeUint32(sec);
        return;
      }
      // Timestamp 64
      // 1970 ... ~2514 with nanoseconds
      _writer
        ..writeUint8(fFixExt8)
        ..writeInt8(extTypeTimestamp)
        ..writeInt64(data64);
    } else {
      // Timestamp 96
      // Before 1970 or after ~2514
      _writer
        ..writeUint8(fExt8)
        ..writeUint8(12) // length
        ..writeInt8(extTypeTimestamp)
        ..writeUint32(nano)
        ..writeInt64(sec);
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
  Uint8List takeBytes() {
    try {
      return _writer.takeBytes();
    } finally {
      BinaryWriterPool.release(_writer);
    }
  }

  /// Disposes of the serializer and releases any resources.
  ///
  /// This method should be called when the serializer is no longer needed to
  /// ensure that any resources (such as buffers) are properly released. After
  ///  calling this method, the serializer should not be used again.
  void dispose() {
    BinaryWriterPool.release(_writer);
  }
}

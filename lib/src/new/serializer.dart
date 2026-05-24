/// MessagePack serializer with a single-callback extension interface.
///
/// Key difference from [../core/serializer.dart]:
/// The old `ExtEncoder` required **two** calls per custom type:
///   1. `extTypeForObject(object)` → `int?`   (hash lookup #1)
///   2. `encodeObject(object)`     → `Uint8List` (hash lookup #2)
///
/// This serializer uses a single [EncodeExt] callback that returns both
/// the ext type ID and the encoded payload in one shot — eliminating the
/// redundant double-lookup at the protocol level.
library;

import 'dart:typed_data';

import 'package:pro_binary/pro_binary.dart';

import '../core/constants.dart';
import '../core/exception.dart';

/// Result of encoding a custom type.
///
/// Contains the extension type ID and the encoded payload bytes.
typedef ExtEncoded = ({int type, Uint8List data});

/// Called by the [Serializer] when it encounters a type it cannot natively
/// handle.
///
/// Should return the ext type ID and encoded payload, or `null` if the
/// object is not a registered custom type.
///
/// This replaces the old two-method `ExtEncoder` interface with a single
/// function call — no more double hash lookups.
typedef EncodeExt = ExtEncoded? Function(Object value);

/// A wrapper for explicitly serializing a [double] as a 32-bit float.
///
/// In MessagePack, Dart's `double` type (64-bit) is serialized as `float 64`
/// by default. Use [Float] to force serialization as `float 32`, saving 4 bytes
/// when full 64-bit precision is not required.
///
/// Example:
/// ```dart
/// final data = serializer.encode(Float(3.14)); // Encoded as float 32
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
/// Uses a single [EncodeExt] callback instead of the two-method `ExtEncoder`
/// interface — eliminating double hash lookups for custom types.
///
/// Example:
/// ```dart
/// final s = Serializer(
///   encodeExt: (value) => switch (value) {
///     MyType() => (type: 1, data: encodeMyType(value)),
///     _ => null,
///   },
/// );
/// s.encode(myObject);
/// final bytes = s.takeBytes();
/// ```
class Serializer {
  /// Creates a [Serializer] instance.
  ///
  /// [encodeExt] — single callback for custom extension types.
  /// [bufferSize] — initial capacity of the internal buffer (default 1024).
  Serializer({
    EncodeExt? encodeExt,
    int bufferSize = 1024,
  }) : _encodeExt = encodeExt {
    _writer = BinaryWriterPool.acquire(bufferSize);
  }

  late final BinaryWriter _writer;
  final EncodeExt? _encodeExt;

  /// Encodes [value] into MessagePack format and writes it to the buffer.
  ///
  /// Supports all standard MessagePack types:
  /// - `null` → nil
  /// - `bool` → true/false
  /// - `int` → positive/negative fixint, uint8-64, int8-64
  /// - `double` → float 64
  /// - [Float] → float 32
  /// - `String` → fixstr, str8-32
  /// - `Uint8List`/`ByteData` → bin8-32
  /// - `Iterable` → fixarray, array16-32
  /// - `Map` → fixmap, map16-32
  /// - `DateTime` → timestamp extension (-1)
  /// - Custom types via [EncodeExt]
  ///
  /// Throws a [MessagePackException] if the value type is not supported.
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
      case _:
        // Single callback — returns (type, data) or null.
        final ext = _encodeExt?.call(value);
        if (ext != null) {
          writeExt(ext.type, ext.data);
          return;
        }
        throw MessagePackUnsupportedTypeException(
          value.runtimeType,
          "Don't know how to serialize type ${value.runtimeType}",
          'Register an extension for this type.',
        );
    }
  }

  @pragma('vm:prefer-inline')
  // The bool parameter is the value being serialized, not a flag.
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
        _writer.writeInt8(value);
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
        _writer.writeUint8(value);
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

    // Optimize for List to avoid iterator overhead.
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

  /// Writes a MessagePack ext format with the given [type] and [data].
  ///
  /// [type] must be in the range -128..127.
  ///
  /// Unlike the old `ExtEncoder.encodeObject`, this method takes the already-
  /// resolved type ID and payload directly — no lookups, no callbacks.
  @pragma('vm:prefer-inline')
  void writeExt(int type, Uint8List data) {
    if (type < -128 || type > 127) {
      throw const MessagePackConfigurationException(
        'Type must be in the range of -128 to 127.',
        'Ensure your custom extension ID is between -128 and 127.',
      );
    }

    final length = data.length;

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
          ..writeUint8(fExt8)
          ..writeUint8(length);
      case <= limitUint16:
        _writer
          ..writeUint8(fExt16)
          ..writeUint16(length);
      case <= limitUint32:
        _writer
          ..writeUint8(fExt32)
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
      ..writeBytes(data);
  }

  @pragma('vm:prefer-inline')
  void writeTimestamp(DateTime value) {
    final micro = (value.isUtc ? value : value.toUtc()).microsecondsSinceEpoch;
    const million = 1_000_000;
    final sec = (micro / million).floor();
    final nano = ((micro % million + million) % million) * 1_000;

    // 0x3FFFFFFFF is max 34-bit unsigned integer
    if (sec >= 0 && sec <= 0x3FFFFFFFF) {
      // Timestamp 32 — 1970..2106, no nanoseconds
      if (nano == 0 && sec <= limitUint32) {
        _writer
          ..writeUint8(fFixExt4)
          ..writeInt8(extTypeTimestamp)
          ..writeUint32(sec);
        return;
      }

      // Timestamp 64 — 1970..~2514, with nanoseconds
      //
      // IMPORTANT: Dart's bitwise operators work on 64-bit integers on native
      // platforms but are restricted to 32 bits on Web (Dart2JS).
      // To ensure cross-platform correctness, we split the 64-bit payload
      // into two 32-bit writes.
      final high32 = (nano << 2) | (sec ~/ 0x100000000);
      final low32 = sec & 0xFFFFFFFF;

      _writer
        ..writeUint8(fFixExt8)
        ..writeInt8(extTypeTimestamp)
        ..writeUint32(high32)
        ..writeUint32(low32);
    } else {
      // Timestamp 96 — before 1970 or after ~2514
      _writer
        ..writeUint8(fExt8)
        ..writeUint8(12)
        ..writeInt8(extTypeTimestamp)
        ..writeUint32(nano)
        ..writeInt64(sec);
    }
  }

  /// Returns the serialized bytes and releases the internal buffer.
  ///
  /// After calling this method, the serializer should not be used again
  /// (use [dispose] if you need to abandon without taking bytes).
  Uint8List takeBytes() {
    try {
      return _writer.takeBytes();
    } finally {
      BinaryWriterPool.release(_writer);
    }
  }

  /// Releases internal resources without returning any data.
  ///
  /// Call this when you need to abandon the serializer (e.g., after an error).
  void dispose() {
    BinaryWriterPool.release(_writer);
  }
}

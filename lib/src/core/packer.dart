/// MessagePack serializer.
///
/// This library provides the [Packer] class, which is a low-level, high-performance
/// MessagePack encoder.
library;

import 'dart:typed_data';

import 'package:pro_binary/pro_binary.dart';

import 'constants.dart';
import 'exception.dart';

/// Result of encoding a custom type.
///
/// Contains the extension type ID and the encoded payload bytes.
typedef ExtEncoded = ({int type, Uint8List data});

/// Called by the [Packer] when it encounters a type it cannot natively
/// handle.
///
/// Returns the extension type ID and encoded payload, or `null` if the
/// object is not a registered custom type.
typedef EncodeExt = ExtEncoded? Function(Object value);

/// A wrapper for explicitly serializing a [double] as a 32-bit float.
///
/// In MessagePack, Dart's `double` type (64-bit) is serialized as `float 64`
/// by default. Use [Float] to force serialization as `float 32`, saving 4 bytes
/// when full 64-bit precision is not required.
///
/// Example:
/// ```dart
/// final data = packer.pack(Float(3.14)); // Encoded as float 32
/// ```
class Float {
  /// Creates a [Float] wrapper for the given [value].
  Float(this.value);

  /// The underlying double value.
  final double value;

  @override
  String toString() => 'Float($value)';
}

/// Internal data structure for the [Packer] extension type.
typedef _Data = ({BinaryWriter writer, EncodeExt? encodeExt});

/// A high-performance MessagePack serializer.
///
/// [Packer] uses a [BinaryWriter] from `pro_binary` to encode Dart objects
/// into the MessagePack binary format. It utilizes a pool-based buffer
/// strategy via `BinaryWriterPool` to minimize memory allocations.
///
/// **Usage:**
/// 1. Create a [Packer] (acquires a writer from the pool).
/// 2. Use [pack] to encode one or more objects.
/// 3. Call [takeBytes] to get the result and release the buffer back to the pool.
///
/// Example:
/// ```dart
/// final packer = Packer();
/// packer.pack({'key': 'value', 'list': [1, 2, 3]});
/// final bytes = packer.takeBytes();
/// ```
extension type Packer._(_Data _data) {
  /// Creates a new [Packer] instance.
  ///
  /// * [encodeExt]: Optional callback for encoding custom extension types.
  /// * [initialBufferSize]: The initial capacity of the internal buffer.
  ///   The buffer will grow automatically if needed.
  Packer({EncodeExt? encodeExt, int initialBufferSize = 1024})
    : _data = (
        writer: BinaryWriterPool.acquire(initialBufferSize),
        encodeExt: encodeExt,
      );

  /// The underlying [BinaryWriter].
  BinaryWriter get _wr => _data.writer;

  /// The custom extension encoder callback.
  EncodeExt? get _ext => _data.encodeExt;

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
  /// Throws a [MessagePackUnsupportedTypeException] if the value type is not
  /// natively supported and no [EncodeExt] was provided or handled the type.
  /// Throws a [MessagePackSizeException] if a string or collection exceeds
  /// the 4GB MessagePack limit.
  void pack(Object? value) {
    switch (value) {
      case null:
        packNull();
      case bool():
        packBool(value);
      case int():
        packInt(value);
      case Float():
        packFloat(value);
      case double():
        packDouble(value);
      case String():
        packString(value);
      case Uint8List():
        packBinary(value);
      case Iterable():
        packArray(value);
      case ByteData():
        packBinary(
          value.buffer.asUint8List(
            value.offsetInBytes,
            value.lengthInBytes,
          ),
        );
      case Map():
        writeMap(value);
      case DateTime():
        packTimestamp(value);
      case _:
        // Single callback — returns (type, data) or null.
        final ext = _ext?.call(value);
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

  /// Packs a `null` value.
  @pragma('vm:prefer-inline')
  void packNull() {
    _wr.writeUint8(fNil);
  }

  /// Packs a boolean [value].
  @pragma('vm:prefer-inline')
  // The bool parameter is the value being serialized, not a flag.
  // ignore: avoid_positional_boolean_parameters
  void packBool(bool value) {
    _wr.writeUint8(value ? fTrue : fFalse);
  }

  /// Packs an integer [value].
  @pragma('vm:prefer-inline')
  void packInt(int value) {
    value >= 0 ? _packPositiveInt(value) : _packNegativeInt(value);
  }

  /// Internal: Packs a positive integer using the most compact format.
  @pragma('vm:prefer-inline')
  void _packPositiveInt(int value) {
    switch (value) {
      case <= limitInt8:
        _wr.writeUint8(value);
      case <= limitUint8:
        _wr
          ..writeUint8(fUint8)
          ..writeUint8(value);
      case <= limitUint16:
        _wr
          ..writeUint8(fUint16)
          ..writeUint16(value);
      case <= limitUint32:
        _wr
          ..writeUint8(fUint32)
          ..writeUint32(value);
      default:
        _wr
          ..writeUint8(fUint64)
          ..writeUint64(value);
    }
  }

  /// Internal: Packs a negative integer using the most compact format.
  @pragma('vm:prefer-inline')
  void _packNegativeInt(int value) {
    switch (value) {
      case >= limitNegFixInt:
        _wr.writeInt8(value);
      case >= limitNegInt8:
        _wr
          ..writeUint8(fInt8)
          ..writeInt8(value);
      case >= limitNegInt16:
        _wr
          ..writeUint8(fInt16)
          ..writeInt16(value);
      case >= limitNegInt32:
        _wr
          ..writeUint8(fInt32)
          ..writeInt32(value);
      default:
        _wr
          ..writeUint8(fInt64)
          ..writeInt64(value);
    }
  }

  /// Packs a [Float] wrapper as a 32-bit float.
  @pragma('vm:prefer-inline')
  void packFloat(Float value) {
    _wr
      ..writeUint8(fFloat32)
      ..writeFloat32(value.value);
  }

  /// Packs a double as a 64-bit float.
  @pragma('vm:prefer-inline')
  void packDouble(double value) {
    _wr
      ..writeUint8(fFloat64)
      ..writeFloat64(value);
  }

  /// Packs a [String] [value] using UTF-8 encoding.
  ///
  /// Throws [MessagePackSizeException] if byte length exceeds [limitUint32].
  @pragma('vm:prefer-inline')
  void packString(String value) {
    final length = getUtf8Length(value);

    switch (length) {
      case <= 31:
        _wr.writeUint8(fFixStrPrefix | length);
      case <= limitUint8:
        _wr
          ..writeUint8(fStr8)
          ..writeUint8(length);
      case <= limitUint16:
        _wr
          ..writeUint8(fStr16)
          ..writeUint16(length);
      case <= limitUint32:
        _wr
          ..writeUint8(fStr32)
          ..writeUint32(length);
      default:
        throw const MessagePackSizeException(
          'String is too long to be serialized with MessagePack.',
          'Ensure string byte length does not exceed 4,294,967,295 bytes.',
        );
    }

    _wr.writeString(value);
  }

  /// Packs binary [bytes].
  ///
  /// Throws [MessagePackSizeException] if length exceeds [limitUint32].
  @pragma('vm:prefer-inline')
  void packBinary(Uint8List bytes) {
    final length = bytes.length;

    switch (length) {
      case <= limitUint8:
        _wr
          ..writeUint8(fBin8)
          ..writeUint8(length);
      case <= limitUint16:
        _wr
          ..writeUint8(fBin16)
          ..writeUint16(length);
      case <= limitUint32:
        _wr
          ..writeUint8(fBin32)
          ..writeUint32(length);
      default:
        throw const MessagePackSizeException(
          'Binary data is too long to be serialized with MessagePack.',
          'Ensure Uint8List size does not exceed 4,294,967,295 bytes.',
        );
    }

    _wr.writeBytes(bytes);
  }

  /// Packs an [iterable] as a MessagePack array.
  ///
  /// Throws [MessagePackSizeException] if length exceeds [limitUint32].
  @pragma('vm:prefer-inline')
  void packArray(Iterable<dynamic> iterable) {
    final length = iterable.length;

    switch (length) {
      case <= 15:
        _wr.writeUint8(fFixArrayPrefix | length);
      case <= limitUint16:
        _wr
          ..writeUint8(fArray16)
          ..writeUint16(length);
      case <= limitUint32:
        _wr
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
        pack(iterable[i]);
      }
    } else {
      for (final item in iterable) {
        pack(item);
      }
    }
  }

  /// Packs a [Map] as a MessagePack map.
  ///
  /// Throws [MessagePackSizeException] if number of entries exceeds [limitUint32].
  @pragma('vm:prefer-inline')
  void writeMap(Map<dynamic, dynamic> dictionary) {
    final length = dictionary.length;

    switch (length) {
      case <= 15:
        _wr.writeUint8(fFixMapPrefix | length);
      case <= limitUint16:
        _wr
          ..writeUint8(fMap16)
          ..writeUint16(length);
      case <= limitUint32:
        _wr
          ..writeUint8(fMap32)
          ..writeUint32(length);
      default:
        throw const MessagePackSizeException(
          'Map is too big to be serialized with MessagePack.',
          'Ensure the Map has no more than 4,294,967,295 key-value pairs.',
        );
    }

    for (final entry in dictionary.entries) {
      pack(entry.key);
      pack(entry.value);
    }
  }

  /// Writes a MessagePack ext format with the given [type] and [data].
  ///
  /// * [type]: Extension type ID (-128..127).
  /// * [data]: Raw binary payload for the extension.
  ///
  /// Throws [MessagePackConfigurationException] if [type] is out of range.
  /// Throws [MessagePackSizeException] if [data] length exceeds [limitUint32].
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
        _wr.writeUint8(fFixExt1);
      case 2:
        _wr.writeUint8(fFixExt2);
      case 4:
        _wr.writeUint8(fFixExt4);
      case 8:
        _wr.writeUint8(fFixExt8);
      case 16:
        _wr.writeUint8(fFixExt16);
      case <= limitUint8:
        _wr
          ..writeUint8(fExt8)
          ..writeUint8(length);
      case <= limitUint16:
        _wr
          ..writeUint8(fExt16)
          ..writeUint16(length);
      case <= limitUint32:
        _wr
          ..writeUint8(fExt32)
          ..writeUint32(length);
      case _:
        throw const MessagePackSizeException(
          'Extension payload is too large.',
          'Ensure the encoded extension data size does not '
              'exceed 4,294,967,295 bytes.',
        );
    }

    _wr
      ..writeInt8(type)
      ..writeBytes(data);
  }

  /// Packs a [DateTime] [value] using the standard MessagePack timestamp extension.
  ///
  /// Automatically chooses between 32-bit, 64-bit, and 96-bit timestamp formats
  /// based on the value's range and precision.
  @pragma('vm:prefer-inline')
  void packTimestamp(DateTime value) {
    final micro = (value.isUtc ? value : value.toUtc()).microsecondsSinceEpoch;
    const million = 1_000_000;
    final sec = (micro / million).floor();
    final nano = ((micro % million + million) % million) * 1_000;

    // 0x3FFFFFFFF is max 34-bit unsigned integer
    if (sec >= 0 && sec <= 0x3FFFFFFFF) {
      // Timestamp 32 — 1970..2106, no nanoseconds
      if (nano == 0 && sec <= limitUint32) {
        _wr
          ..writeUint8(fFixExt4)
          ..writeInt8(extTypeTimestamp)
          ..writeUint32(sec);
        return;
      }

      // Timestamp 64 — 1970..~2514, with nanoseconds.
      //
      // IMPORTANT: MessagePack TS64 format stores nanoseconds in the upper
      // 30 bits and seconds in the lower 34 bits of an 8-byte unsigned integer.
      //
      // Dart's bitwise operators work on 64-bit integers on native platforms
      // but are restricted to 32 bits on Web (Dart2JS).
      // To ensure cross-platform correctness, we split the 64-bit payload
      // into two 32-bit writes.
      final high32 = (nano << 2) | (sec ~/ 0x100000000);
      final low32 = sec & 0xFFFFFFFF;

      _wr
        ..writeUint8(fFixExt8)
        ..writeInt8(extTypeTimestamp)
        ..writeUint32(high32)
        ..writeUint32(low32);
    } else {
      // Timestamp 96 — before 1970 or after ~2514
      _wr
        ..writeUint8(fExt8)
        ..writeUint8(12)
        ..writeInt8(extTypeTimestamp)
        ..writeUint32(nano)
        ..writeInt64(sec);
    }
  }

  /// Packs multiple [values] sequentially.
  void packAll(Iterable<dynamic> values) {
    for (final value in values) {
      pack(value);
    }
  }

  /// Appends [bytes] directly to the buffer without any encoding.
  ///
  /// Use this only when [bytes] are already in MessagePack format. This is
  /// highly efficient for concatenating pre-encoded fragments.
  void appendRaw(Uint8List bytes) {
    _wr.writeBytes(bytes);
  }

  /// Returns the serialized bytes and releases the internal buffer back to the pool.
  ///
  /// **Warning:** After calling this method, the [Packer] instance is disposed
  /// and cannot be used again.
  Uint8List takeBytes() {
    try {
      return _wr.takeBytes();
    } finally {
      BinaryWriterPool.release(_wr);
    }
  }

  /// Releases internal resources back to the pool without returning any data.
  ///
  /// Call this when you need to abandon the serializer (e.g., after an error).
  void dispose() {
    BinaryWriterPool.release(_wr);
  }
}

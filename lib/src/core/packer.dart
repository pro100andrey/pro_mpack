/// MessagePack serializer.
///
/// This library provides the [Packer] class, which is a low-level,
/// high-performance
/// MessagePack encoder.
library;

import 'dart:typed_data';

import 'package:pro_binary/pro_binary.dart';

import 'constants.dart';
import 'exception.dart';
import 'timestamp.dart';

/// Called by the [Packer] when it encounters a type it cannot natively
/// handle.
///
/// Writes the extension data directly to the provided [packer] and returns
/// `true` if handled, or `false` if the object is not a registered custom type.
typedef EncodeExt = bool Function(dynamic value, Packer packer);

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

/// Internal packer state structure for the [Packer] extension type.
typedef _PackerState = ({BinaryWriter writer, dynamic encodeExt});

/// The single ext-header format table: maps an extension payload [length] to
/// its `(marker, headerSize)`. Consulted by both ext-write strategies — the
/// reserve-then-shift path in `packExt` and the forward-write path in
/// `_writeExtHeader` — so the two cannot disagree on framing.
///
/// `headerSize` is the total header byte count including the marker and the
/// 1-byte type: `2` for fixext (no length field), `3`/`4`/`6` for ext8/16/32.
/// Lengths above [limitUint16] map to ext32; callers that cannot shift handle
/// the `> limitUint32` overflow themselves.
@pragma('vm:prefer-inline')
(int marker, int headerSize) _extHeaderFor(int length) => switch (length) {
  1 => (fFixExt1, 2),
  2 => (fFixExt2, 2),
  4 => (fFixExt4, 2),
  8 => (fFixExt8, 2),
  16 => (fFixExt16, 2),
  <= limitUint8 => (fExt8, 3),
  <= limitUint16 => (fExt16, 4),
  _ => (fExt32, 6),
};

/// A high-performance MessagePack serializer.
///
/// [Packer] uses a [BinaryWriter] from `pro_binary` to encode Dart objects
/// into the MessagePack binary format. It utilizes a pool-based buffer
/// strategy via `BinaryWriterPool` to minimize memory allocations.
///
/// **Usage:**
/// 1. Create a [Packer] (acquires a writer from the pool).
/// 2. Use [pack] to encode one or more objects.
/// 3. Call [takeBytes] to get the result and release the buffer back to the
/// pool.
///
/// Example:
/// ```dart
/// final packer = Packer();
/// packer.pack({'key': 'value', 'list': [1, 2, 3]});
/// final bytes = packer.takeBytes();
/// ```
extension type Packer._(_PackerState _st) {
  /// Creates a new [Packer] instance.
  ///
  /// * [encodeExt]: Optional callback for encoding custom extension types.
  /// * [initialBufferSize]: The initial capacity of the internal buffer.
  ///   The buffer will grow automatically if needed.
  Packer({EncodeExt? encodeExt, int initialBufferSize = 1024})
    : _st = (
        writer: BinaryWriterPool.acquire(initialBufferSize),
        encodeExt: encodeExt,
      );

  /// Encodes a single [value] to bytes, owning the full pool lifecycle.
  ///
  /// Acquires a [Packer], packs [value], returns its bytes, and always releases
  /// the buffer back to the pool — even on error. Use this instead of the
  /// acquire/`takeBytes`/`finally dispose` dance by hand.
  @pragma('vm:prefer-inline')
  static Uint8List encode(
    dynamic value, {
    EncodeExt? encodeExt,
    int initialBufferSize = 1024,
  }) {
    final p = Packer(
      encodeExt: encodeExt,
      initialBufferSize: initialBufferSize,
    );
    try {
      p.pack(value);
      return p.takeBytes();
    } finally {
      p.dispose();
    }
  }

  /// Encodes a sequence of [values] into one buffer, owning the pool lifecycle.
  ///
  /// The values are concatenated with no top-level array; the buffer is always
  /// released back to the pool, even on error.
  static Uint8List encodeAll(
    Iterable<dynamic> values, {
    EncodeExt? encodeExt,
    int initialBufferSize = 1024,
  }) {
    final p = Packer(
      encodeExt: encodeExt,
      initialBufferSize: initialBufferSize,
    );
    try {
      for (final value in values) {
        p.pack(value);
      }
      return p.takeBytes();
    } finally {
      p.dispose();
    }
  }

  /// The underlying [BinaryWriter].
  @pragma('vm:prefer-inline')
  BinaryWriter get _wr => _st.writer;

  /// The custom extension encoder callback.
  @pragma('vm:prefer-inline')
  EncodeExt? get _ext => _st.encodeExt as EncodeExt?;

  /// The number of bytes currently written to the internal buffer.
  @pragma('vm:prefer-inline')
  int get bytesWritten => _wr.bytesWritten;

  /// Packs a boolean [value].
  @pragma('vm:prefer-inline')
  void packBool(bool? value) => value == null ? packNull() : _packBool(value);

  /// Packs an integer [value].
  @pragma('vm:prefer-inline')
  void packInt(int? value) => value == null ? packNull() : _packInt(value);

  /// Packs a [Float] wrapper as a 32-bit float.
  @pragma('vm:prefer-inline')
  void packFloat(Float? value) =>
      value == null ? packNull() : _packFloat(value);

  /// Packs a double as a 64-bit float.
  @pragma('vm:prefer-inline')
  void packDouble(double? value) =>
      value == null ? packNull() : _packDouble(value);

  /// Packs a [String] [value] using UTF-8 encoding.
  ///
  /// Throws [MessagePackSizeException] if byte length exceeds [limitUint32].
  @pragma('vm:prefer-inline')
  void packString(String? value) =>
      value == null ? packNull() : _packString(value);

  /// Packs a binary [value].
  ///
  /// Throws [MessagePackSizeException] if length exceeds [limitUint32].
  @pragma('vm:prefer-inline')
  void packBinary(Uint8List? value) =>
      value == null ? packNull() : _packBinary(value);

  /// Packs a [value] as a MessagePack array.
  ///
  /// Throws [MessagePackSizeException] if length exceeds [limitUint32].
  @pragma('vm:prefer-inline')
  void packArray(Iterable<dynamic>? value) =>
      value == null ? packNull() : _packArray(value);

  /// Packs a [Map] as a MessagePack map.
  ///
  /// Throws [MessagePackSizeException] if number of entries exceeds
  /// [limitUint32].
  @pragma('vm:prefer-inline')
  void packMap(Map<dynamic, dynamic>? value) =>
      value == null ? packNull() : _packMap(value);

  /// Writes only the MessagePack array header for an array of [count] elements
  /// (`fixarray`/`array16`/`array32`).
  ///
  /// The caller must then write exactly [count] values with the typed pack
  /// methods. This is the low-level dual of [packArray] for encoding an array
  /// element-by-element without building an intermediate collection; the bytes
  /// are identical to [packArray] over the equivalent values.
  ///
  /// Throws [MessagePackSizeException] if [count] exceeds [limitUint32].
  @pragma('vm:prefer-inline')
  void packArrayLength(int count) {
    switch (count) {
      case <= 15:
        _wr.writeUint8(fFixArrayPrefix | count);
      case <= limitUint16:
        _wr
          ..writeUint8(fArray16)
          ..writeUint16(count);
      case <= limitUint32:
        _wr
          ..writeUint8(fArray32)
          ..writeUint32(count);
      default:
        throw const MessagePackSizeException(
          'Array is too big to be serialized with MessagePack.',
          'Ensure the Iterable has no more than 4,294,967,295 elements.',
        );
    }
  }

  /// Writes only the MessagePack map header for a map of [count] entries
  /// (`fixmap`/`map16`/`map32`).
  ///
  /// The caller must then write exactly [count] key/value pairs with the typed
  /// pack methods. This is the low-level dual of [packMap] for encoding a map
  /// entry-by-entry without building an intermediate collection; the bytes are
  /// identical to [packMap] over the equivalent entries.
  ///
  /// Throws [MessagePackSizeException] if [count] exceeds [limitUint32].
  @pragma('vm:prefer-inline')
  void packMapLength(int count) {
    switch (count) {
      case <= 15:
        _wr.writeUint8(fFixMapPrefix | count);
      case <= limitUint16:
        _wr
          ..writeUint8(fMap16)
          ..writeUint16(count);
      case <= limitUint32:
        _wr
          ..writeUint8(fMap32)
          ..writeUint32(count);
      default:
        throw const MessagePackSizeException(
          'Map is too big to be serialized with MessagePack.',
          'Ensure the Map has no more than 4,294,967,295 key-value pairs.',
        );
    }
  }

  /// Packs a [DateTime] [value] using the standard MessagePack timestamp
  /// extension.
  ///
  /// Automatically chooses between 32-bit, 64-bit, and 96-bit timestamp formats
  /// based on the value's range and precision.
  @pragma('vm:prefer-inline')
  void packTimestamp(DateTime? value) =>
      value == null ? packNull() : _packTimestamp(value);

  //Base

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
  @pragma('vm:prefer-inline')
  void pack(dynamic value) {
    switch (value) {
      case null:
        packNull();
      case bool():
        _packBool(value);
      case int():
        _packInt(value);
      case Float():
        _packFloat(value);
      case double():
        _packDouble(value);
      case String():
        _packString(value);
      case Uint8List():
        _packBinary(value);
      case Iterable():
        _packArray(value);
      case ByteData():
        _packBinary(
          value.buffer.asUint8List(
            value.offsetInBytes,
            value.lengthInBytes,
          ),
        );
      case Map():
        _packMap(value);
      case DateTime():
        _packTimestamp(value);
      case _:
        // Callback writes directly to this Packer if it handles the type.
        if (_ext != null && (_ext!).call(value, this)) {
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

  /// Packs a custom extension payload.
  ///
  /// The [builder] receives the current [Packer] to write the payload.
  /// Uses zero-allocation in-place buffer shifting to dynamically calculate
  /// the extension header size after the payload is written.
  @pragma('vm:prefer-inline')
  void packExt(int type, void Function(Packer) builder) {
    if (type < -128 || type > 127) {
      throw const MessagePackConfigurationException(
        'Type must be in the range of -128 to 127.',
        'Ensure your custom extension ID is between -128 and 127.',
      );
    }

    const maxHeaderSize = 6; // Max header size for ext formats (ext32)

    final startPos = _wr.reserve(maxHeaderSize);

    builder(this);

    final payloadLength = _wr.bytesWritten - startPos - maxHeaderSize;

    final (marker, headerSize) = _extHeaderFor(payloadLength);

    if (headerSize < maxHeaderSize) {
      _wr.shiftBytes(
        startPos + maxHeaderSize,
        _wr.bytesWritten,
        startPos + headerSize,
      );
    }

    _wr.setUint8(startPos, marker);

    switch (headerSize) {
      case 2:
        _wr.setUint8(startPos + 1, type);
      case 3:
        _wr.setUint8(startPos + 1, payloadLength);
        _wr.setUint8(startPos + 2, type);
      case 4:
        _wr.setUint16(startPos + 1, payloadLength);
        _wr.setUint8(startPos + 3, type);
      case 6:
        _wr.setUint32(startPos + 1, payloadLength);
        _wr.setUint8(startPos + 5, type);
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
  void packRawExtension(int type, Uint8List data) {
    if (type < -128 || type > 127) {
      throw const MessagePackConfigurationException(
        'Type must be in the range of -128 to 127.',
        'Ensure your custom extension ID is between -128 and 127.',
      );
    }

    _writeExtHeader(type, data.length);
    _wr.writeBytes(data);
  }

  @pragma('vm:prefer-inline')
  void _writeExtHeader(int type, int length) {
    if (length > limitUint32) {
      throw const MessagePackSizeException(
        'Extension payload is too large.',
        'Ensure the encoded extension data size does not '
            'exceed 4,294,967,295 bytes.',
      );
    }

    final (marker, headerSize) = _extHeaderFor(length);

    _wr.writeUint8(marker);
    switch (headerSize) {
      case 3:
        _wr.writeUint8(length);
      case 4:
        _wr.writeUint16(length);
      case 6:
        _wr.writeUint32(length);
      // headerSize 2 → fixext, no length field
    }

    _wr.writeInt8(type);
  }

  /// Packs a boolean [value].
  @pragma('vm:prefer-inline')
  void _packBool(bool value) {
    _wr.writeUint8(value ? fTrue : fFalse);
  }

  /// Packs an integer [value].
  @pragma('vm:prefer-inline')
  void _packInt(int value) {
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
  void _packFloat(Float value) {
    _wr
      ..writeUint8(fFloat32)
      ..writeFloat32(value.value);
  }

  /// Packs a double as a 64-bit float.
  @pragma('vm:prefer-inline')
  void _packDouble(double value) {
    _wr
      ..writeUint8(fFloat64)
      ..writeFloat64(value);
  }

  /// Packs a [String] [value] using UTF-8 encoding.
  ///
  /// Encodes the body in a single UTF-8 pass: it reserves the maximum string
  /// header, writes the body once (so the string is never scanned twice — once
  /// to size and once to write), then backpatches the smallest valid header and
  /// shifts the body left over the unused reserve. Same Reserve & Backpatch
  /// pattern as [packExt]; output is byte-identical to the two-pass form.
  ///
  /// Throws [MessagePackSizeException] if byte length exceeds [limitUint32].
  @pragma('vm:prefer-inline')
  void _packString(String value) {
    // Empty string short-circuits the reserve/shift: the trailing-block shift
    // can't reclaim reserved space when the body is zero-length.
    if (value.isEmpty) {
      _wr.writeUint8(fFixStrPrefix);
      return;
    }

    const maxHeaderSize = 5; // str32: 1 marker + 4 length bytes

    final startPos = _wr.reserve(maxHeaderSize);

    _wr.writeString(value); // single UTF-8 pass

    final length = _wr.bytesWritten - startPos - maxHeaderSize;

    final (marker, headerSize) = switch (length) {
      <= 31 => (fFixStrPrefix | length, 1),
      <= limitUint8 => (fStr8, 2),
      <= limitUint16 => (fStr16, 3),
      <= limitUint32 => (fStr32, 5),
      _ => throw const MessagePackSizeException(
        'String is too long to be serialized with MessagePack.',
        'Ensure string byte length does not exceed 4,294,967,295 bytes.',
      ),
    };

    if (headerSize < maxHeaderSize) {
      _wr.shiftBytes(
        startPos + maxHeaderSize,
        _wr.bytesWritten,
        startPos + headerSize,
      );
    }

    _wr.setUint8(startPos, marker);

    switch (headerSize) {
      case 2:
        _wr.setUint8(startPos + 1, length);
      case 3:
        _wr.setUint16(startPos + 1, length);
      case 5:
        _wr.setUint32(startPos + 1, length);
      // headerSize 1 → fixstr, marker already encodes the length
    }
  }

  /// Packs a binary [value].
  ///
  /// Throws [MessagePackSizeException] if length exceeds [limitUint32].
  @pragma('vm:prefer-inline')
  void _packBinary(Uint8List value) {
    final length = value.length;

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

    _wr.writeBytes(value);
  }

  /// Packs a [value] as a MessagePack array.
  ///
  /// Throws [MessagePackSizeException] if length exceeds [limitUint32].
  @pragma('vm:prefer-inline')
  void _packArray(Iterable<dynamic> value) {
    final length = value.length;

    packArrayLength(length);

    // Optimize for List to avoid iterator overhead.
    if (value is List) {
      for (var i = 0; i < length; i++) {
        pack(value[i]);
      }
    } else {
      for (final item in value) {
        pack(item);
      }
    }
  }

  /// Packs a [Map] as a MessagePack map.
  ///
  /// Throws [MessagePackSizeException] if number of entries exceeds
  /// [limitUint32].
  @pragma('vm:prefer-inline')
  void _packMap(Map<dynamic, dynamic> value) {
    packMapLength(value.length);

    for (final entry in value.entries) {
      pack(entry.key);
      pack(entry.value);
    }
  }

  /// Packs a [DateTime] [value] using the standard MessagePack timestamp
  /// extension.
  ///
  /// Automatically chooses between 32-bit, 64-bit, and 96-bit timestamp formats
  /// based on the value's range and precision.
  @pragma('vm:prefer-inline')
  void _packTimestamp(DateTime value) {
    MessagePackTimestamp.encode(_wr, value);
  }

  /// Appends [bytes] directly to the buffer without any encoding.
  ///
  /// Use this only when [bytes] are already in MessagePack format. This is
  /// highly efficient for concatenating pre-encoded fragments.
  @pragma('vm:prefer-inline')
  void appendRaw(Uint8List bytes) {
    _wr.writeBytes(bytes);
  }

  /// Returns the serialized bytes and releases the internal buffer back to the
  /// pool.
  ///
  /// * [copy]: If `true` (default), returns a copy of the bytes, allowing the
  ///   internal buffer to be safely reused or returned to the pool. If `false`,
  ///   returns a direct view of the buffer, which avoids allocation but is only
  ///   valid until the buffer is modified or released.
  /// * [dispose]: If `true` (default), the internal buffer is returned to the
  ///   pool, and this [Packer] instance is disposed and cannot be used again.
  ///   Set to `false` to keep writing to the same packer
  ///  (useful for streaming).
  @pragma('vm:prefer-inline')
  Uint8List takeBytes({bool copy = true, bool dispose = true}) {
    try {
      final result = _wr.takeBytes(copy: copy);
      return result;
    } finally {
      if (dispose) {
        BinaryWriterPool.release(_wr);
      }
    }
  }

  /// Releases internal resources back to the pool without returning any data.
  ///
  /// Call this when you need to abandon the serializer (e.g., after an error).
  @pragma('vm:prefer-inline')
  void dispose() {
    BinaryWriterPool.release(_wr);
  }
}

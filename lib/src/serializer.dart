import 'dart:convert';
import 'dart:typed_data';

import 'package:pro_binary/pro_binary.dart';

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
  /// Throws an [Exception] if the object cannot be encoded.
  Uint8List encodeObject(Object? object);
}

/// A class representing a custom floating-point number.
class Float {
  Float(this.value);

  final double value;

  @override
  String toString() => value.toString();
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
  void encode(Object? value) {
    switch (value) {
      case null:
        _writer.writeUint8(0xc0 /*nil*/);
      case bool():
        _writer.writeUint8(value ? 0xc3 /*true*/ : 0xc2 /*false*/);
      case int() when value < 0:
        _writeNegativeInt(value);
      case int() when value >= 0:
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
      case _ when _extEncoder != null && _writeExt(value):
        ;
      case _:
        throw Exception("Don't know how to serialize $value");
    }
  }

  /// Returns the serialized bytes as a Uint8List.
  /// After calling this method, the serializer is reset and can be used again.
  Uint8List takeBytes() => _writer.takeBytes();

  void _writeNegativeInt(int value) {
    switch (value) {
      case >= -32:
        _writer.writeInt8(value /*negative fixint*/);
      case >= -128:
        _writer
          ..writeUint8(0xd0 /*int 8*/)
          ..writeInt8(value);
      case >= -32768:
        _writer
          ..writeUint8(0xd1 /*int 16*/)
          ..writeInt16(value);
      case >= -2147483648:
        _writer
          ..writeUint8(0xd2 /*int 32*/)
          ..writeInt32(value);
      case _:
        _writer
          ..writeUint8(0xd3 /*int 64*/)
          ..writeInt64(value);
    }
  }

  void _writePositiveInt(int value) {
    switch (value) {
      case <= 127:
        _writer.writeUint8(value); //positive fixint
      case <= 255:
        _writer
          ..writeUint8(0xcc /*uint 8*/)
          ..writeUint8(value);
      case <= 65535:
        _writer
          ..writeUint8(0xcd /*uint 16*/)
          ..writeUint16(value);
      case <= 4294967295:
        _writer
          ..writeUint8(0xce /*uint 32*/)
          ..writeUint32(value);
      case _:
        _writer
          ..writeUint8(0xcf /*uint 64*/)
          ..writeUint64(value);
    }
  }

  void _writeFloat(Float value) {
    _writer
      ..writeUint8(0xca /*float 32*/)
      ..writeFloat32(value.value);
  }

  void _writeDouble(double value) {
    _writer
      ..writeUint8(0xcb /*float 64*/)
      ..writeFloat64(value);
  }

  void _writeString(String value) {
    final encoded = const Utf8Encoder().convert(value);
    final length = encoded.length;

    switch (length) {
      case <= 31:
        _writer.writeUint8(0xa0 /*fixstr*/ | length);
      case <= 255:
        _writer
          ..writeUint8(0xd9 /*str 8*/)
          ..writeUint8(length);
      case <= 65535:
        _writer
          ..writeUint8(0xda /*str 16*/)
          ..writeUint16(length);
      case <= 4294967295:
        _writer
          ..writeUint8(0xdb /*str 32*/)
          ..writeUint32(length);
      case _:
        throw Exception(
          'String is too long to be serialized with messagePack.',
        );
    }

    _writer.writeBytes(encoded);
  }

  void _writeBinary(Uint8List buffer) {
    final length = buffer.length;

    switch (length) {
      case <= 0xff:
        _writer
          ..writeUint8(0xc4 /*bin 8*/)
          ..writeUint8(length);

      case <= 65535:
        _writer
          ..writeUint8(0xc5 /*bin 16*/)
          ..writeUint16(length);
      case <= 4294967295:
        _writer
          ..writeUint8(0xc6 /*bin 32*/)
          ..writeUint32(length);
      case _:
        throw Exception(
          'Data is too long to be serialized with messagePack.',
        );
    }

    _writer.writeBytes(buffer);
  }

  void _writeIterable(Iterable iterable) {
    final length = iterable.length;

    switch (length) {
      case <= 15:
        _writer.writeUint8(0x90 /*fixarray*/ | length);
      case <= 65535:
        _writer
          ..writeUint8(0xdc /*array 16*/)
          ..writeUint16(length);
      case <= 4294967295:
        _writer
          ..writeUint8(0xdd /*array 32*/)
          ..writeUint32(length);
      case _:
        throw Exception(
          'Array is too big to be serialized with messagePack',
        );
    }

    iterable.forEach(encode);
  }

  void _writeMap(Map dictionary) {
    final length = dictionary.length;

    switch (length) {
      case <= 15:
        _writer.writeUint8(0x80 /*fixmap*/ | length);
      case <= 65535:
        _writer
          ..writeUint8(0xde /*map 16*/)
          ..writeUint16(length);
      case <= 4294967295:
        _writer
          ..writeUint8(0xdf /*map 32*/)
          ..writeUint32(length);
      case _:
        throw Exception(
          'Map is too big to be serialized with messagePack',
        );
    }

    for (final item in dictionary.entries) {
      encode(item.key);
      encode(item.value);
    }
  }

  bool _writeExt(object) {
    final type = _extEncoder?.extTypeForObject(object);

    if (type != null) {
      final encoded = _extEncoder?.encodeObject(object);

      if (encoded == null) {
        throw Exception('Unable to encode object. No Encoder specified.');
      }

      final length = encoded.length;

      switch (length) {
        case 1:
          _writer.writeUint8(0xd4);
        case 2:
          _writer.writeUint8(0xd5);
        case 4:
          _writer.writeUint8(0xd6);
        case 8:
          _writer.writeUint8(0xd7);
        case 16:
          _writer.writeUint8(0xd8);
        case <= 0xff:
          _writer
            ..writeUint8(0xc7) // ext8
            ..writeUint8(length);
        case <= 0xFFFF:
          _writer
            ..writeUint8(0xc8) // ext16
            ..writeUint16(length);
        case <= 0xFFFFFFFF:
          _writer
            ..writeUint8(0xc9) // ext32
            ..writeUint32(length);
        case _:
          throw Exception('Size must be at most 0xFFFFFFFF');
      }

      if (type < -128 || type > 127) {
        throw Exception('Type must be in the range of -128 to 127');
      }

      _writer
        ..writeInt8(type)
        ..writeBytes(encoded);

      return true;
    }

    return false;
  }
}

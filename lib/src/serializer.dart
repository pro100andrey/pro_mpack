import 'dart:convert';
import 'dart:typed_data';

import 'package:pro_binary/pro_binary.dart';

///
mixin ExtEncoder {
  /// Returns the extension type for a given [object].
  ///
  /// Returns `null` if the [object] cannot be encoded as an extension type.
  int? extTypeForObject(Object? object);

  /// Encodes a given [object] into a Uint8List.
  ///
  /// Returns a Uint8List representing the encoded object.
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
  Serializer({
    ExtEncoder? extEncoder,
  }) : _extEncoder = extEncoder;

  final _writer = BinaryWriter();
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
        _writer.writeUint8(value); // negative fixint
      case >= -128:
        _writer
          ..writeUint8(0xd0 /*int 8*/)
          ..writeInt8(value);
      case >= -32768:
        _writer
          ..writeUint8(0xd1)
          ..writeInt16(value /*int 16*/);
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

      _writer
        ..writeUint8(type)
        ..writeBytes(encoded);

      return true;
    }

    return false;
  }
}

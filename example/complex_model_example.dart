// For example purposes only
// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:typed_data';

import 'package:pro_binary/pro_binary.dart';
import 'package:pro_mpack/pro_mpack.dart';

// --- Data Models ---

class Device {
  Device({required this.id, required this.model});
  final int id;
  final String model;

  @override
  String toString() => 'Device(id: $id, model: $model)';
}

class Address {
  Address({required this.street, required this.zip});
  final String street;
  final int zip;

  @override
  String toString() => 'Address(street: $street, zip: $zip)';
}

class User {
  User({
    required this.id,
    required this.name,
    required this.address,
    required this.devices,
  });

  final int id;
  final String name;
  final Address address;
  final List<Device> devices;

  @override
  String toString() =>
      'User(id: $id, name: $name, address: $address, devices: $devices)';
}

// --- Custom Extension Handler ---

// Define a unique extension type ID for User
const extTypeUser = 10;

/// An optimized Codec for the User model.
///
/// This demonstrates "Minimal Overhead" by manually packing fields into a
/// binary format inside the extension payload, rather than serializing to an
/// intermediate Map.
class UserCodec with ExtEncoder implements ExtDecoder {
  // --- Encoder Implementation ---

  @override
  int? extTypeForObject(Object? object) {
    if (object is User) {
      return extTypeUser;
    }
    return null;
  }

  @override
  Uint8List encodeObject(Object? object) {
    if (object is User) {
      // Manual binary packing for minimal overhead.
      // Layout:
      // - id: uint32
      // - name: utf8 bytes (prefixed with uint16 length)
      // - address.street: utf8 bytes (prefixed with uint16 length)
      // - address.zip: uint32
      // - devices.count: uint16
      // - devices: array of [id: uint32, model: utf8 (uint16 len)]

      final writer = BinaryWriter(initialBufferSize: 256)
        ..writeUint32(object.id);
      _writeString(writer, object.name);

      // Inline Address
      _writeString(writer, object.address.street);
      writer
        ..writeUint32(object.address.zip)
        // Inline Devices
        ..writeUint16(object.devices.length);
      for (final device in object.devices) {
        writer.writeUint32(device.id);
        _writeString(writer, device.model);
      }

      return writer.takeBytes();
    }
    throw MessagePackError('Unknown type');
  }

  void _writeString(BinaryWriter writer, String value) {
    final bytes = utf8.encode(value);
    writer
      ..writeUint16(bytes.length)
      ..writeBytes(Uint8List.fromList(bytes));
  }

  // --- Decoder Implementation ---

  @override
  Object? decodeObject(int extType, Uint8List data) {
    if (extType == extTypeUser) {
      final reader = BinaryReader(data);

      final id = reader.readUint32();
      final name = _readString(reader);

      final street = _readString(reader);
      final zip = reader.readUint32();
      final address = Address(street: street, zip: zip);

      final deviceCount = reader.readUint16();
      final devices = <Device>[];
      for (var i = 0; i < deviceCount; i++) {
        final devId = reader.readUint32();
        final devModel = _readString(reader);
        devices.add(Device(id: devId, model: devModel));
      }

      return User(id: id, name: name, address: address, devices: devices);
    }
    throw UnimplementedError();
  }

  String _readString(BinaryReader reader) {
    final length = reader.readUint16();
    // pro_binary's readString usually expects bytes count if it wraps readBytes
    // But BinaryReader.readString(len) reads bytes and decodes utf8
    return reader.readString(length);
  }
}

void main() {
  // Create a complex model
  final user = User(
    id: 12345,
    name: 'Alice Wonderland',
    address: Address(street: 'Rabbit Hole 42', zip: 99999),
    devices: [
      Device(id: 1, model: 'Pixel 8'),
      Device(id: 2, model: 'MacBook Pro'),
    ],
  );

  print('Original User: $user');

  // Serialize using custom codec
  final codec = UserCodec();
  final bytes = serialize(user, extEncoder: codec);

  print('Serialized bytes: ${bytes.length} bytes');
  print('Bytes: $bytes');

  // Deserialize
  final decodedUser = deserialize(bytes, extDecoder: codec);

  print('Decoded User: $decodedUser');

  // Verify
  assert(
    decodedUser.toString() == user.toString(),
    'Decoded user does not match original!',
  );
  print('Verification passed!');
}

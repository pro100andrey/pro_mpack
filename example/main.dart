// Print deserialized data
// ignore_for_file: avoid_print

import 'dart:typed_data';

import 'package:pro_mpack/pro_mpack.dart';

final createdAt = DateTime.utc(3000, 1, 1, 12, 32, 5, 999, 999);
final updatedAt = DateTime.utc(1969, 12, 31, 23, 59, 59, 999, 999);

abstract class Model {
  const Model();
}

class User extends Model {
  const User({
    required this.name,
    required this.age,
    required this.created,
    required this.updated,
  });

  final String name;
  final int age;
  final DateTime created;
  final DateTime updated;
}

class Product extends Model {
  Product(this.price);
  final int price;
}

Uint8List _bigIntEncoder(BigInt value) =>
    Uint8List.fromList(value.toString().codeUnits);

BigInt _bigIntDecoder(Uint8List data) =>
    BigInt.parse(String.fromCharCodes(data));

final modelRegistry = MsgPackSubRegistry<Model>()
  ..register<User>(
    subId: 1,
    encoder: (u) => serializeAll([u.name, u.age, u.created, u.updated]),
    decoder: (d) {
      final fields = deserializeAll(d).cast<Object>();

      final name = fields[0] as String;
      final age = fields[1] as int;
      final createdAt = fields[2] as DateTime;
      final updatedAt = fields[3] as DateTime;

      return User(name: name, age: age, created: createdAt, updated: updatedAt);
    },
  )
  ..register<Product>(
    subId: 2,
    encoder: (p) => Uint8List.fromList([p.price]),
    decoder: (d) => Product(d[0]),
  );

final bigIntExtension = MsgPackExtension.create<BigInt>(
  typeId: 1,
  encoder: (value) => Uint8List.fromList(value.toString().codeUnits),
  decoder: (data) => BigInt.parse(String.fromCharCodes(data)),
);

final registry = MsgPackRegistry([
  modelRegistry.asExtension(2),
  bigIntExtension,
]);

final codec = MessagePackCodec(registry: registry);

void main() {
  final now = DateTime.now().toUtc();
  final userData = {
    'id': 1,
    'name': 'John Doe',
    'current': now,
    'created': createdAt,
    'updated': updatedAt,
    'balance': BigInt.parse('123456789012345678901234567890'),
  };

  print('$userData');

  final bytes = userData.toMsgPack(codec: codec);
  final deserializedData = bytes
      .fromMsgPack<Map>(codec: codec)
      .cast<String, Object?>();

  print(deserializedData);

  final user = User(
    name: 'Alice',
    age: 30,
    created: createdAt,
    updated: updatedAt,
  );

  final userBytes = user.toMsgPack(codec: codec);

  final decodedUser = userBytes.fromMsgPack<User>(codec: codec);

  print('User name: ${decodedUser.name}');
}

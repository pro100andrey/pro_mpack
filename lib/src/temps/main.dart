import 'dart:io';
import 'dart:typed_data';

import 'pack.dart';
import 'unpack.dart';

void main(List<String> args) {
  final user = User(
    id: '10000',
    name: 'Alice',
    age: 22,
    created: .now().toUtc(),
  );

  stdout.writeln(user);

  final userData = user.encode();

  stdout.writeln('$userData, len: ${userData.lengthInBytes}');

  final unpackedUser = UserPackUnpack.decode(userData);

  stdout.writeln(unpackedUser);
}

class User {
  const User({
    required this.id,
    required this.name,
    required this.age,
    required this.created,
  });

  final String id;
  final String name;
  final int age;
  final DateTime created;

  @override
  String toString() =>
      'User(id: $id, name: $name, age: $age, created: $created)';
}

extension UserPackUnpack on User {
  Uint8List encode() {
    final pack = Pack()
      ..packString(id)
      ..packString(name)
      ..packInt(age)
      ..pack(created);

    return pack.takeBytes();
  }

  static User decode(Uint8List buffer) {
    final unpack = Unpack(buffer: buffer);

    final result = User(
      id: unpack.unpackString(),
      name: unpack.unpackString(),
      age: unpack.unpackInt(),
      created: unpack.unpack()! as DateTime,
    );

    return result;
  }
}

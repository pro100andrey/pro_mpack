import 'package:pro_mpack/src/message_pack.dart';

import 'models.dart';

final mpack = MessagePack(
  extensions: (mp) {
    mp
      ..register(
        extId: 1,
        encoder: (value, p) => p.packString(value.toString()),
        decoder: (u, l) => BigInt.parse(u.unpackString()!),
        polymorphic: true,
      )
      ..registerGroup(
        extId: 2,
        builder: (group) => group
          ..addressCodec()
          ..userCodec()
          ..productCodec(),
      )
      ..registerGroup(
        extId: 3,
        builder: (group) => group
          ..circleCodec()
          ..rectangleCodec(),
      );
  },
);

extension ShapeMessagePackGroup on MessagePackGroup {
  void circleCodec() => add(
    subId: 1,
    encoder: (value, p) => p.packDouble(value.radius),
    decoder: (u, l) => Circle(u.unpackDouble()!),
  );

  void rectangleCodec() => add(
    subId: 2,
    encoder: (rectangle, packer) {
      packer
        ..packDouble(rectangle.width)
        ..packDouble(rectangle.height);
    },
    decoder: (unpacker, _) {
      final width = unpacker.unpackDouble()!;
      final height = unpacker.unpackDouble()!;

      return Rectangle(width, height);
    },
  );
}

extension AddressMessagePackGroup on MessagePackGroup {
  void addressCodec() => add(
    subId: 1,
    encoder: (address, packer) {
      packer
        ..packString(address.street)
        ..packString(address.city)
        ..packInt(address.zipCode);
    },
    decoder: (unpacker, _) {
      final street = unpacker.unpackString()!;
      final city = unpacker.unpackString()!;
      final zipCode = unpacker.unpackInt()!;

      return Address(street: street, city: city, zipCode: zipCode);
    },
  );
}

extension UserMessagePackGroup on MessagePackGroup {
  void userCodec() => add<User>(
    subId: 2,
    encoder: (user, packer) {
      packer
        ..packInt(user.id)
        ..packString(user.name)
        ..packInt(user.age)
        ..packString(user.email)
        ..packTimestamp(user.created)
        ..packTimestamp(user.updated)
        ..packBinary(user.data)
        ..packArray(user.addresses)
        ..packArray(user.numbers)
        ..pack(user.bigValue);
    },
    decoder: (unpacker, l) {
      final id = unpacker.unpackInt()!;
      final name = unpacker.unpackString()!;
      final age = unpacker.unpackInt()!;
      final email = unpacker.unpackString()!;
      final created = unpacker.unpackTimestamp()!;
      final updated = unpacker.unpackTimestamp()!;
      final data = unpacker.unpackBinary()!;
      final addresses = unpacker.unpackArray()!;
      final numbers = unpacker.unpackArray()!;
      final bigValue = unpacker.unpack() as BigInt;

      return User(
        id: id,
        name: name,
        age: age,
        email: email,
        created: created,
        updated: updated,
        data: data,
        addresses: addresses.cast(),
        numbers: numbers.cast(),
        bigValue: bigValue,
      );
    },
  );
}

extension ProductMessagePackGroup on MessagePackGroup {
  void productCodec() => add<Product>(
    subId: 3,
    encoder: (product, packer) {
      packer
        ..packString(product.title)
        ..packString(product.description)
        ..pack(product.price);
    },
    decoder: (unpacker, _) {
      final title = unpacker.unpackString()!;
      final description = unpacker.unpackString()!;
      final price = unpacker.unpack() as BigInt;

      return Product(title: title, description: description, price: price);
    },
  );
}

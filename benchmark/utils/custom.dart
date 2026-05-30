import 'dart:typed_data';

import 'package:pro_mpack/src/message_pack.dart';

import 'models.dart';

final mpack = MessagePack(
  extensions: (mp) {
    mp
      ..register(
        extId: 1,
        encoder: (value, ctx) => ctx.pack(value.toString()),
        decoder: (data, ctx) => BigInt.parse(ctx.unpack(data)),
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
    encoder: (value, ctx) => ctx.pack(value.radius),
    decoder: (data, ctx) => Circle(ctx.unpack(data)),
  );

  void rectangleCodec() => add(
    subId: 2,
    encoder: (value, ctx) => ctx.packAll(
      [value.width, value.height],
    ),
    decoder: (data, ctx) {
      final [double width, double height] = ctx.unpackAll(data);

      return Rectangle(width, height);
    },
  );
}

extension AddressMessagePackGroup on MessagePackGroup {
  void addressCodec() => add(
    subId: 1,
    encoder: (address, ctx) => ctx.packAll(
      [address.street, address.city, address.zipCode],
    ),
    decoder: (data, ctx) {
      final [String street, String city, int zipCode] = ctx.unpackAll(data);

      return Address(street: street, city: city, zipCode: zipCode);
    },
  );
}

extension UserMessagePackGroup on MessagePackGroup {
  void userCodec() => add<User>(
    subId: 2,
    encoder: (user, ctx) => ctx.packAll([
      user.id,
      user.name,
      user.age,
      user.email,
      user.created,
      user.updated,
      user.data,
      user.addresses,
      user.numbers,
      user.bigValue,
    ]),
    decoder: (data, ctx) {
      final [
        int id,
        String name,
        int age,
        String email,
        DateTime created,
        DateTime updated,
        Uint8List d,
        List<dynamic> addresses,
        List<dynamic> numbers,
        BigInt bigValue,
      ] = ctx.unpackAll(
        data,
      );

      return User(
        id: id,
        name: name,
        age: age,
        email: email,
        created: created,
        updated: updated,
        data: d,
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
    encoder: (product, ctx) => ctx.packAll(
      [product.title, product.description, product.price],
    ),
    decoder: (data, ctx) {
      final [String title, String description, BigInt price] = ctx.unpackAll(
        data,
      );

      return Product(title: title, description: description, price: price);
    },
  );
}

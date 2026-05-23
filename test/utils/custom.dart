import 'dart:typed_data';

import 'package:pro_mpack/src/message_pack_new.dart';

import 'models.dart';

final mpack = MessagePack(
  extensions: (mp) {
    mp
      ..register(
        extId: 1,
        encoder: (value, ctx) => ctx.pack(value.toString()),
        decoder: (data, ctx) => BigInt.parse(ctx.unpack<String>(data)),
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
        builder: (group) => group..circleCodec(),
      );
  },
);

extension ShapeMessagePackGroup on MessagePackGroup {
  void circleCodec() => add(
    subId: 1,
    encoder: (value, ctx) => ctx.pack(value.radius),
    decoder: (data, ctx) {
      final radius = ctx.unpack<double>(data);
      return Circle(radius);
    },
  );

  void rectangleCodec() => add(
    subId: 1,

    encoder: (value, ctx) => ctx.packAll([value.width, value.height]),
    decoder: (data, ctx) {
      final values = ctx.unpackAll<dynamic>(data);
      final [width as double, height as double] = values;

      return Rectangle(width, height);
    },
  );
}

extension AddressMessagePackGroup on MessagePackGroup {
  void addressCodec() => add(
    subId: 1,
    encoder: (address, ctx) {
      final fields = [
        address.street,
        address.city,
        address.zipCode,
      ];
      return ctx.packAll(fields);
    },
    decoder: (data, ctx) {
      final values = ctx.unpackAll<Object?>(data);

      final [
        street as String,
        city as String,
        zipCode as int,
      ] = values;

      return Address(
        street: street,
        city: city,
        zipCode: zipCode,
      );
    },
  );
}

extension UserMessagePackGroup on MessagePackGroup {
  void userCodec() => add<User>(
    subId: 2,
    encoder: (user, ctx) {
      final fields = [
        user.id,
        user.name,
        user.age,
        user.email,
        user.created,
        user.updated,
        user.data,
        user.addresses,
        user.numbers,
      ];
      return ctx.packAll(fields);
    },
    decoder: (data, ctx) {
      final fields = ctx.unpackAll<Object?>(data);

      final [
        id as int,
        name as String,
        age as int,
        email as String,
        created as DateTime,
        updated as DateTime,
        d as Uint8List,
        addresses as List<Object?>,
        numbers as List<Object?>,
      ] = fields;

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
      );
    },
  );
}

extension ProductMessagePackGroup on MessagePackGroup {
  void productCodec() => add<Product>(
    subId: 3,
    encoder: (product, ctx) {
      final fields = [
        product.title,
        product.description,
        product.price,
      ];
      return ctx.packAll(fields);
    },
    decoder: (data, ctx) {
      final fields = ctx.unpackAll<Object?>(data);

      final [
        title as String,
        description as String,
        price as BigInt,
      ] = fields;

      return Product(
        title: title,
        description: description,
        price: price,
      );
    },
  );
}

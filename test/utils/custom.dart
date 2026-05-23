import 'dart:typed_data';

import 'package:pro_mpack/pro_mpack.dart';

import 'models.dart';

final mpack = MessagePack(
  extensions: (config) {
    config
      ..registerBigInt()
      ..registerGroup<dynamic>(
        extId: 2,
        builder: (group) => group
          ..addressCodec()
          ..userCodec()
          ..productCodec(),
      );
  },
);

// For compatibility with performance tests
class _CodecMock {
  _CodecMock(this.mpack);

  final MessagePack mpack;

  Uint8List encode(Object? value) => mpack.pack(value);

  T decode<T>(Uint8List data) => mpack.unpack<T>(data);
}

final codec = _CodecMock(mpack);

extension BigIntMessagePack on MessagePack {
  void registerBigInt() => register<BigInt>(
    extId: 1,
    encoder: (value, ctx) => ctx.pack(value.toString()),
    decoder: (data, ctx) => BigInt.parse(ctx.unpack<String>(data)),
  );
}

extension AddressMessagePackGroup on MessagePackGroup {
  void addressCodec() => add<Address>(
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

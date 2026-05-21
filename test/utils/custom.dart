import 'package:pro_mpack/message_pack.dart';

import 'models.dart';

final mpack = MessagePack(
  extensions: (config) {
    config
      ..register<BigInt>(
        extId: 1,
        encoder: (value, ctx) => ctx.pack(value.toString()),
        decoder: (data, ctx) => BigInt.parse(ctx.unpack<String>(data)!),
      )
      ..registerGroup(
        extId: 2,
        builder: (group) {
          group
            ..add<Address>(
              typeId: 1,
              encoder: (address, ctx) => ctx.packAll([
                address.street,
                address.city,
                address.zipCode,
              ]),
              decoder: (data, ctx) {
                final [street as String, city as String, zipCode as int] = ctx
                    .unpackAll(data);
                return Address(street: street, city: city, zipCode: zipCode);
              },
            )
            ..add<User>(
              typeId: 2,
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
              ]),
              decoder: (data, ctx) {
                final fields = ctx.unpackAll(data);
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
            )
            ..add<Product>(
              typeId: 3,
              encoder: (product, ctx) => ctx.packAll([
                product.title,
                product.description,
                product.price,
              ]),
              decoder: (data, ctx) {
                final [t as String, desc as String, price as BigInt] = ctx
                    .unpackAll(data);
                return Product(
                  title: t,
                  description: desc,
                  price: price,
                );
              },
            );
        },
      );
  },
);

// For compatibility with performance tests that might use 'codec'
class _CodecMock {
  _CodecMock(this.mpack);
  final MessagePack mpack;
  Uint8List encode(Object? value) => mpack.pack(value);
  T decode<T>(Uint8List data) => mpack.unpack<T>(data) as T;
}

final codec = _CodecMock(mpack);

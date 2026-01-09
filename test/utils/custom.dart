import 'dart:typed_data';

import 'package:pro_mpack/pro_mpack.dart';

import 'models.dart';

final bigIntExt = MessagePackExtension.create<BigInt>(
  typeId: 1,
  encoder: (value, reg) => reg.pack(value.toString()),
  decoder: (data, reg) => BigInt.parse(reg.unpack(data)),
);

final modelSubRegistry = MessagePackSubRegistry()
    .add(
      subId: 1,
      encoder: (address, reg) => reg.packAll(
        [
          address.street,
          address.city,
          address.zipCode,
        ],
      ),
      decoder: (data, reg) {
        final fields = reg.unpackAll(data);
        final [street as String, city as String, zipCode as int] = fields;

        return Address(street: street, city: city, zipCode: zipCode);
      },
    )
    .add(
      subId: 2,
      encoder: (user, reg) => reg.packAll(
        [
          user.id,
          user.name,
          user.age,
          user.email,
          user.created,
          user.updated,
          user.data,
          user.addresses,
          user.numbers,
        ],
      ),
      decoder: (data, reg) {
        final fields = reg.unpackAll(data);
        final [
          id as int,
          name as String,
          age as int,
          email as String,
          created as DateTime,
          updated as DateTime,
          d as Uint8List,
          addresses as List,
          numbers as List,
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
    .add(
      subId: 3,
      encoder: (product, reg) =>
          reg.packAll([product.title, product.description, product.price]),
      decoder: (data, reg) {
        final fields = reg.unpackAll(data);
        final [t as String, desc as String, price as BigInt] = fields;

        return Product(
          title: t,
          description: desc,
          price: price,
        );
      },
    );

/// Create the main registry and register extensions and sub-registries.
final registry = MessagePackRegistry()
  ..register(bigIntExt)
  ..registerSub(2, modelSubRegistry);

/// Create a codec using the registry.
final codec = MessagePackCodec(registry: registry);

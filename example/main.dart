// Disable warnings for print statements in this example
// ignore_for_file: avoid_print

import 'package:pro_mpack/pro_mpack.dart';

void main() {
  final mp = MessagePack(
    extensions: (config) {
      config
        // Register a custom codec for BigInt, which is not natively
        // supported by MessagePack
        ..registerBigInt()
        // Group for user-related types
        ..registerGroup<dynamic>(
          extId: 2,
          builder: (group) => group
            ..userCodec()
            ..addressCodec()
            ..productCodec(),
        );
    },
  );

  final user = User(
    id: 1,
    name: 'Alice',
    age: 30,
    email: 'alice@example.com',
    created: DateTime.utc(2023),
    updated: DateTime.utc(2023, 1, 2),
    addresses: [
      const Address(street: '123 Main St', city: 'New York', zipCode: 10001),
    ],
    products: [
      Product(
        title: 'Gadget',
        description: 'A useful gadget',
        price: BigInt.parse('123456789012345678901234567890'),
      ),
    ],
  );

  final userBytes = mp.pack(user);
  final decodedUser = mp.unpack<User>(userBytes);

  print('Decoded User: $decodedUser');
  print('Bytes: ${userBytes.length}');
}

class Address {
  const Address({
    required this.street,
    required this.city,
    required this.zipCode,
  });

  final String street;
  final String city;
  final int zipCode;

  @override
  String toString() => 'Address(street: $street, city: $city, zip: $zipCode)';
}

class User {
  const User({
    required this.id,
    required this.name,
    required this.age,
    required this.email,
    required this.created,
    required this.updated,
    required this.addresses,
    required this.products,
  });

  final int id;
  final String name;
  final int age;
  final String email;
  final DateTime created;
  final DateTime updated;
  final List<Address> addresses;
  final List<Product> products;

  @override
  String toString() =>
      'User(id: $id, name: $name, age: $age, email: $email, created: $created, '
      'updated: $updated, addresses: $addresses, products: $products)';
}

class Product {
  Product({
    required this.description,
    required this.price,
    required this.title,
  });

  final BigInt price;
  final String description;
  final String title;

  @override
  String toString() =>
      'Product(title: $title, description: $description, price: $price)';
}

extension BigIntMessagePack on MessagePack {
  void registerBigInt() => register<BigInt>(
    extId: 1,
    encoder: (value, ctx) => ctx.pack(value.toString()),
    decoder: (data, ctx) => BigInt.parse(ctx.unpack<String>(data)),
  );
}

extension UserMessagePackGroup on MessagePackGroup {
  void userCodec() => add<User>(
    subId: 100,
    encoder: (user, ctx) {
      final fields = [
        user.id,
        user.name,
        user.age,
        user.email,
        user.created,
        user.updated,
        user.addresses,
        user.products,
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
        adds as List,
        products as List,
      ] = fields;

      return User(
        id: id,
        name: name,
        age: age,
        email: email,
        created: created,
        updated: updated,
        addresses: adds.cast(),
        products: products.cast(),
      );
    },
  );
}

extension AddressMessagePackGroup on MessagePackGroup {
  void addressCodec() => add<Address>(
    subId: 200,
    encoder: (addr, ctx) {
      final fields = [
        addr.street,
        addr.city,
        addr.zipCode,
      ];

      return ctx.packAll(fields);
    },
    decoder: (data, ctx) {
      final fields = ctx.unpackAll<Object?>(data);

      final [
        street as String,
        city as String,
        zipCode as int,
      ] = fields;

      return Address(street: street, city: city, zipCode: zipCode);
    },
  );
}

extension ProductMessagePackGroup on MessagePackGroup {
  void productCodec() => add<Product>(
    subId: 300,
    encoder: (product, ctx) {
      final fields = [product.description, product.price, product.title];
      return ctx.packAll(fields);
    },
    decoder: (data, ctx) {
      final fields = ctx.unpackAll<Object?>(data);

      final [
        description as String,
        price as BigInt,
        title as String,
      ] = fields;

      return Product(description: description, price: price, title: title);
    },
  );
}

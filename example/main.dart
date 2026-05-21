// Disable warnings for print statements in this example
// ignore_for_file: avoid_print

import 'package:pro_mpack/message_pack.dart';

void main() {
  final mpack = MessagePack(
    extensions: (config) {
      config
        ..register<BigInt>(
          extId: 1,
          encoder: BigIntMessagePack.encode,
          decoder: BigIntMessagePack.decode,
        )
        // Declarative registration of models group
        ..registerGroup(
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

  final userBytes = mpack.pack(user);
  final decodedUser = mpack.unpack<User>(userBytes);

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

extension BigIntMessagePack on BigInt {
  static Uint8List encode(BigInt value, MessagePackContext ctx) {
    final str = value.toString();

    return ctx.pack(str);
  }

  static BigInt decode(Uint8List data, MessagePackContext ctx) {
    final str = ctx.unpack<String>(data)!;
    return BigInt.parse(str);
  }
}

extension UserMessagePackGroup on MessagePackGroup {
  void userCodec() => add(
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
      final fields = ctx.unpackAll(data);

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
  void addressCodec() => add(
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
      final fields = ctx.unpackAll(data);

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
  void productCodec() => add(
    subId: 300,
    encoder: (product, ctx) {
      final fields = [product.description, product.price, product.title];
      return ctx.packAll(fields);
    },
    decoder: (data, ctx) {
      final fields = ctx.unpackAll(data);

      final [
        description as String,
        price as BigInt,
        title as String,
      ] = fields;

      return Product(description: description, price: price, title: title);
    },
  );
}

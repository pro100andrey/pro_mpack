// Ignore file for demonstration purposes
// ignore_for_file: avoid_print

import 'package:pro_mpack/pro_mpack.dart';

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
    required this.name,
    required this.age,
    required this.created,
    required this.updated,
    required this.addresses,
  });

  final String name;
  final int age;
  final DateTime created;
  final DateTime updated;
  final List<Address> addresses;

  @override
  String toString() =>
      'User(name: $name, age: $age, created: $created, updated: $updated, '
      'addresses: $addresses)';
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

final bigIntExt = MessagePackExtension.create<BigInt>(
  typeId: 1,
  encoder: (u, reg) => reg.pack(u.toString()),
  decoder: (d, reg) => BigInt.parse(reg.unpack(d)),
);

final modelSubRegistry = MessagePackSubRegistry()
    .add(
      subId: 1,
      encoder: (address, reg) =>
          reg.packAll([address.street, address.city, address.zipCode]),
      decoder: (data, reg) {
        final fields = reg.unpackAll(data);
        final [s as String, c as String, z as int] = fields;

        return Address(street: s, city: c, zipCode: z);
      },
    )
    .add(
      subId: 2,
      encoder: (user, reg) => reg.packAll(
        [user.name, user.age, user.created, user.updated, user.addresses],
      ),
      decoder: (data, reg) {
        final fields = reg.unpackAll(data);
        final [
          n as String,
          a as int,
          c as DateTime,
          u as DateTime,
          adds as List,
        ] = fields;

        return User(
          name: n,
          age: a,
          created: c,
          updated: u,
          addresses: adds.cast(),
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

void main() {
  print('=== Basic Serialization ===');
  final createdAt = DateTime.utc(3000, 1, 1, 12, 32, 5, 999, 999);
  final updatedAt = DateTime.utc(1969, 12, 31, 23, 59, 59, 999, 999);
  final user = User(
    name: 'Alice',
    age: 30,
    created: createdAt,
    updated: updatedAt,
    addresses: [
      const Address(street: '123 Main St', city: 'New York', zipCode: 10001),
      const Address(street: '456 Oak Ave', city: 'Los Angeles', zipCode: 90001),
    ],
  );

  // Using extension methods
  final userBytes = user.encode(codec: codec);
  final decodedUser = userBytes.decode<User>(codec: codec);

  print('Original: $user');
  print('Decoded:  $decodedUser');
  print('Bytes: ${userBytes.length} bytes');

  print('\n=== Product with BigInt ===');
  final product = Product(
    title: 'Gadget',
    description: 'A useful gadget',
    price: BigInt.parse('12345678901234567890'),
  );

  final productBytes = product.encode(codec: codec);
  final decodedProduct = productBytes.decode<Product>(codec: codec);
  print(decodedProduct);
  print('Bytes: ${productBytes.length} bytes');
}

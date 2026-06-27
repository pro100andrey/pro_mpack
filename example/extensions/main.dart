// Custom extensions in depth.
//
// Registers a polymorphic extension for an external type (`BigInt`, whose
// hidden runtime type is `_BigIntImpl`), plus two extension groups packing
// related models (`User`, `Address`, `Product`) under single extension IDs to
// bypass the 256-ID limit. Decoding uses type-safe `unpackArrayOf<T>()` and
// `unpackAs<T>()`.
//
// Run: `dart run example/extensions/main.dart`

import 'dart:io';
import 'dart:typed_data';

import 'package:pro_mpack/pro_mpack.dart';

final mp = MessagePack(
  extensions: (config) {
    config
      // Register a custom extension for BigInt
      ..register(
        extId: 1,
        // BigInt.parse() returns a _BigIntImpl, we need polymorphic
        // registration
        polymorphic: true,
        encoder: (i, p) => p.packBinary(bigIntToBytes(i)),
        decoder: (u, l) => bytesToBigInt(u.unpackBinary()!),
      )
      // Register a group for our custom classes: User, Address
      ..registerGroup(
        extId: 2,
        builder: (group) => group
          ..add(
            subId: 1,
            encoder: (u, p) => p
              ..packInt(u.id)
              ..packString(u.name)
              ..packInt(u.age)
              ..packString(u.email)
              ..packTimestamp(u.created)
              ..packTimestamp(u.updated)
              ..packArray(u.addresses)
              ..packArray(u.products),
            decoder: (u, l) => User(
              id: u.unpackInt()!,
              name: u.unpackString()!,
              age: u.unpackInt()!,
              email: u.unpackString()!,
              created: u.unpackTimestamp()!,
              updated: u.unpackTimestamp()!,
              addresses: u.unpackArrayOf<Address>(),
              products: u.unpackArrayOf<Product>(),
            ),
          )
          ..add(
            subId: 2,
            encoder: (addr, p) => p
              ..packString(addr.street)
              ..packString(addr.city)
              ..packInt(addr.zipCode),
            decoder: (u, l) => Address(
              street: u.unpackString()!,
              city: u.unpackString()!,
              zipCode: u.unpackInt()!,
            ),
          ),
      )
      // Register a group for Product, which contains BigInt as a field
      ..registerGroup(
        extId: 3,
        builder: (group) => group
          ..add(
            subId: 1,
            encoder: (product, p) => p
              ..packString(product.title)
              ..packString(product.description)
              ..pack(product.price),

            decoder: (u, l) => Product(
              title: u.unpackString()!,
              description: u.unpackString()!,
              price: u.unpackAs<BigInt>(),
            ),
          ),
      );
  },
);

void main() {
  final users = generateUsers(100).toList();
  final bytes = mp.pack(users);
  stdout.writeln('Serialized ${bytes.length} bytes');

  final decodedUsers = mp.unpack<List<dynamic>>(bytes).cast<User>();

  log('Original users: ${users.length}');
  log('Decoded users: ${decodedUsers.length}');
}

Iterable<User> generateUsers(int count) sync* {
  for (var i = 0; i < count; i++) {
    yield User(
      id: i + 1,
      name: 'User $i',
      age: 20 + (i % 30),
      email: 'user$i@example.com',
      created: DateTime.utc(2020 + (i % 4)),
      updated: DateTime.utc(2021 + (i % 3)),
      addresses: [
        const Address(
          street: '123 Main St',
          city: 'City',
          zipCode: 10000,
        ),
      ],
      products: [
        Product(
          title: 'Product $i',
          description: 'Description for product $i',
          price:
              BigInt.parse('10000000000000${i}00000000000000') + BigInt.from(i),
        ),
      ],
    );
  }
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

/// Big-endian, two's-complement-free byte encoding of a non-negative [BigInt].
Uint8List bigIntToBytes(BigInt number) {
  if (number == BigInt.zero) {
    return Uint8List.fromList([0]);
  }

  final byteLength = (number.bitLength + 7) >> 3;
  return Uint8List.fromList(
    List<int>.generate(byteLength, (i) {
      final shift = (byteLength - 1 - i) * 8;
      return ((number >> shift) & BigInt.from(255)).toInt();
    }),
  );
}

BigInt bytesToBigInt(Uint8List bytes) => bytes.fold(
  BigInt.zero,
  (result, byte) => (result << 8) | BigInt.from(byte),
);

void log([Object? object = '']) => stdout.writeln(object);

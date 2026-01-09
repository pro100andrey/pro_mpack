import 'dart:typed_data';

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
    required this.data,
    required this.addresses,
    required this.numbers,
  });

  final int id;
  final String name;
  final int age;
  final String email;
  final DateTime created;
  final DateTime updated;
  final Uint8List data;
  final List<Address> addresses;
  final List<int> numbers;

  @override
  String toString() =>
      'User(id: $id, name: $name, age: $age, email: $email, created: $created, '
      'updated: $updated, data length: ${data.length}, addresses: $addresses, '
      'numbers: $numbers)';
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

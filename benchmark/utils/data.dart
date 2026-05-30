import 'dart:typed_data';

import 'models.dart';

final object = {
  'type': 'User',
  'id': 1,
  'name': 'John Doe',
  'age': 30,
  'nil': null,
  'email': 'this.andrey@gmail.com',
  'start': DateTime(100, 1, 1, 12, 23, 34, 567, 890),
  'end': DateTime(3000, 1, 1, 12, 23, 34, 567, 890),
  'data': Uint8List.fromList(List.generate(100, (index) => index)),
  'addresses': [
    {
      'type': 'Address',
      'id': 1,
      'street': 'Street 124',
    },
    {
      'type': 'Address',
      'id': 2,
      'street': 'Street 152',
    },
    {
      'type': 'Address',
      'id': 3,
      'street': 'Street 52a',
    },
    {
      'type': 'Address',
      'id': 4,
      'street': 'Street 52b',
    },
  ],
  'list': [1, 2, 3, 4, 5, 6, 7, 8, 8, 10],
  '0': {
    1: 'Address',
    2: 'Street 124',
    3: 'Street 152',
  },
};

final user = User(
  id: 1,
  name: 'Alice',
  age: 30,
  email: 'alice@example.com',
  created: DateTime.utc(3000, 1, 1, 12, 32, 5, 999, 999),
  updated: DateTime.utc(1969, 12, 31, 23, 59, 59, 999, 999),
  data: Uint8List.fromList(List.generate(100, (index) => index)),
  addresses: [
    const Address(
      street: '123 Main St',
      city: 'New York',
      zipCode: 10001,
    ),
    const Address(
      street: '456 Oak Ave',
      city: 'Los Angeles',
      zipCode: 90001,
    ),
    const Address(
      street: '789 Pine Rd',
      city: 'Chicago',
      zipCode: 60601,
    ),
  ],
  numbers: [1, 2, 3, 4, 5, 6, 7, 8, 8, 10],
  bigValue: .parse('1234567890987654321234567890'),
);

const rectangle = Rectangle(10, 20);

const circle = Circle(100);

final product = Product(
  title: 'Item',
  description: 'Item description',
  price: .parse('1234567898765432123456789'),
);

import 'dart:typed_data';

final object = {
  'type': 'User',
  'id': 1,
  'name': 'John Doe',
  'age': 30,
  'nil': null,
  'email': 'this.andrey@gmail.com',
  'start': DateTime(1985, 1, 1, 12, 23, 34),
  'end': DateTime(1988, 1, 1, 12, 23, 34),
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
    }
  ],
  'list': [1, 2, 3, 4, 5, 6, 7, 8, 8, 10],
  '0': {
    1: 'Address',
    2: 'Street 124',
    3: 'Street 152',
  },
};

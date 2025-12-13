// Print deserialized data
// ignore_for_file: avoid_print

import 'package:pro_mpack/pro_mpack.dart';

void main() {
  final createdAt = DateTime.utc(3000, 1, 1, 12, 32, 5, 999, 999);
  final updatedAt = DateTime.utc(1969, 12, 31, 23, 59, 59, 999, 999);
  final now = DateTime.now().toUtc();
  final userData = {
    'id': 1,
    'name': 'John Doe',
    'current': now,
    'created': createdAt,
    'updated': updatedAt,
  };

  print('$userData');

  final data = serialize(userData);
  final deserializedData = deserialize(data);

  print(deserializedData);
}

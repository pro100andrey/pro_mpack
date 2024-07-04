import 'dart:typed_data';

import 'package:benchmark_harness/benchmark_harness.dart';
import 'package:pro_mpack/pro_mpack.dart';

final object = {
  'type': 'User',
  'id': 1,
  'name': 'John Doe',
  'age': 30,
  'email': 'this.andrey@gmail.com',
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
  ],
  'list': [1, 2, 3, 4, 5, 6, 7, 8, 8, 10],
};

class SerializerBenchmark extends BenchmarkBase {
  SerializerBenchmark() : super('mpack - serialize');

  @override
  void run() {
    serialize(object);

    final _ = serialize(object);
  }

  @override
  void exercise() => run();

  @override
  void setup() {
    // Set up any initial state here
  }

  @override
  void teardown() {
    // Clean up any resources here
  }
}

void main() {
  SerializerBenchmark().report();
}

import 'package:benchmark_harness/benchmark_harness.dart';
import 'package:pro_mpack/pro_mpack.dart';

import 'utils/custom.dart';
import 'utils/data.dart';
import 'utils/models.dart';

class SerializerBenchmark extends BenchmarkBase {
  SerializerBenchmark(this.iterations) : super('mpack - serialize');

  final int iterations;

  @override
  void run() {
    for (var i = 0; i < iterations; i++) {
      final _ = serialize(object);
    }
  }

  @override
  void exercise() => run();
}

class SerializerModelsBenchmark extends BenchmarkBase {
  SerializerModelsBenchmark() : super('mpack - serialize models');

  final object = User(
    id: 1,
    name: 'Alice',
    age: 30,
    email: 'alice@example.com',
    created: DateTime.utc(3000, 1, 1, 12, 32, 5, 999, 999),
    updated: DateTime.utc(1969, 12, 31, 23, 59, 59, 999, 999),
    data: .fromList(List.generate(100, (index) => index)),
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
  );

  // final object = {
  //   'type': 'User',
  //   'id': 1,
  //   'name': 'John Doe',
  //   'age': 30,
  //   'nil': null,
  //   'email': 'this.andrey@gmail.com',
  //   'start': DateTime(100, 1, 1, 12, 23, 34, 567, 890),
  //   'end': DateTime(3000, 1, 1, 12, 23, 34, 567, 890),
  //   'data': Uint8List.fromList(List.generate(100, (index) => index)),
  //   'addresses': [
  //     {
  //       'type': 'Address',
  //       'id': 1,
  //       'street': 'Street 124',
  //     },
  //     {
  //       'type': 'Address',
  //       'id': 2,
  //       'street': 'Street 152',
  //     },
  //     {
  //       'type': 'Address',
  //       'id': 3,
  //       'street': 'Street 52a',
  //     },
  //     {
  //       'type': 'Address',
  //       'id': 4,
  //       'street': 'Street 52b',
  //     },
  //   ],
  //   'list': [1, 2, 3, 4, 5, 6, 7, 8, 8, 10],
  //   '0': {
  //     1: 'Address',
  //     2: 'Street 124',
  //     3: 'Street 152',
  //   },
  // };

  @override
  void run() {
    for (var i = 0; i < 1000; i++) {
      final encoded = object.encode(codec: codec);
      if (encoded.length != 251) {
        throw Exception('Invalid encoded length: ${encoded.length}');
      }
    }
  }

  @override
  void exercise() => run();
}

void main() {
  // SerializerBenchmark(1000).report();
  SerializerModelsBenchmark().report();
}

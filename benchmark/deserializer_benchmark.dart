import 'dart:typed_data';

import 'package:benchmark_harness/benchmark_harness.dart';
import 'package:pro_mpack/pro_mpack.dart';

import 'utils/custom.dart';
import 'utils/data.dart';
import 'utils/models.dart';

class DeserializerBenchmark extends BenchmarkBase {
  DeserializerBenchmark() : super('mpack - deserialize');

  late final Uint8List bytes;

  @override
  void setup() {
    bytes = serialize(object);
  }

  @override
  void run() {
    for (var i = 0; i < 1000; i++) {
      final result = deserialize(bytes);

      final _ = result;
    }
  }

  @override
  void exercise() => run();
}

class DeserializerModelsBenchmark extends BenchmarkBase {
  DeserializerModelsBenchmark() : super('mpack - deserialize models');

  late final Uint8List bytes;

  @override
  void setup() {
    bytes = mpack.encode([user, circle, rectangle, product]);
  }

  @override
  void run() {
    for (var i = 0; i < 1000; i++) {
      final [
        User user,
        Circle circle,
        Rectangle rectangle,
        Product product,
      ] = mpack.decode(bytes) as List;

      final _ = user;
      final _ = circle;
      final _ = rectangle;
      final _ = product;
    }
  }

  @override
  void exercise() => run();
}

void main() {
  DeserializerBenchmark().report();
  DeserializerModelsBenchmark().report();
}

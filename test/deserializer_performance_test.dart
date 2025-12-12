import 'dart:typed_data';

import 'package:benchmark_harness/benchmark_harness.dart';
import 'package:pro_mpack/pro_mpack.dart';

import 'utils/data.dart';

class DeserializerBenchmark extends BenchmarkBase {
  DeserializerBenchmark(this.iterations) : super('mpack - deserialize');

  final int iterations;

  late final Uint8List bytes;
  @override
  void setup() {
    bytes = serialize(object);
  }

  @override
  void run() {
    for (var i = 0; i < iterations; i++) {
      final _ = deserialize(bytes);
    }
  }

  @override
  void exercise() => run();
}

void main() {
  DeserializerBenchmark(1000).report();
}

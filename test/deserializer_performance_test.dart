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
      final _ = deserialize(bytes);
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
    bytes = codec.encode(user);
  }

  @override
  void run() {
    for (var i = 0; i < 1000; i++) {
      final _ = codec.decode<User>(bytes);
    }
  }

  @override
  void exercise() => run();
}

void main() {
  DeserializerBenchmark().report();
  DeserializerModelsBenchmark().report();
}

import 'package:benchmark_harness/benchmark_harness.dart';
import 'package:pro_mpack/pro_mpack.dart';

import 'utils/custom.dart';
import 'utils/data.dart';

class SerializerBenchmark extends BenchmarkBase {
  const SerializerBenchmark() : super('mpack - serialize');

  @override
  void run() {
    for (var i = 0; i < 1000; i++) {
      final encoded = serialize(object);

      if (encoded.length != 421) {
        throw Exception('Invalid encoded length: ${encoded.length}');
      }
    }
  }

  @override
  void exercise() => run();
}

class SerializerModelsBenchmark extends BenchmarkBase {
  SerializerModelsBenchmark() : super('mpack - serialize models');

  @override
  void run() {
    for (var i = 0; i < 1000; i++) {
      final encoded = user.encode(codec: codec);
      if (encoded.length != 251) {
        throw Exception('Invalid encoded length: ${encoded.length}');
      }
    }
  }

  @override
  void exercise() => run();
}

void main() {
  const SerializerBenchmark().report();
  SerializerModelsBenchmark().report();
}

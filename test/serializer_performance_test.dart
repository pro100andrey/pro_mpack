import 'package:benchmark_harness/benchmark_harness.dart';
import 'package:pro_mpack/pro_mpack.dart';

import 'utils/data.dart';
import 'utils/utils.dart';

class SerializerBenchmark extends BenchmarkBase {
  SerializerBenchmark(this.iterations) : super('mpack - serialize');

  final int iterations;

  @override
  void run() {
    for (var i = 0; i < iterations; i++) {
      final _ = serialize(
        object,
        extEncoder: CustomTypesExtEncoder(
          timeStampFormat: TimeStampFormat.ts96,
        ),
      );
    }
  }
}

void main() {
  SerializerBenchmark(1000).report();
}

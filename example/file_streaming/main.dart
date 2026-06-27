// Big-data file streaming — constant-memory read/write of a large binary file.
//
// Writes 1,000,000 market ticks to a file with a custom header (magic bytes +
// version) followed by a MessagePack metadata map and a continuous stream of
// `[timestamp, price, volume, isBuy]` arrays, batching writes by reusing one
// [Packer] (`takeBytes(dispose: false)`). It then parses the file
// incrementally through `streamDecoder`, never loading it fully into RAM.
//
// On-disk layout:
// 1. Magic bytes `[0x4D, 0x4B, 0x54, 0x31]` ("MKT1") — 4 bytes
// 2. Version — 1 byte
// 3. Metadata — a MessagePack map (exchange, symbol, …)
// 4. Data — continuous MessagePack arrays `[timestamp, price, volume, isBuy]`
//
// Run: `dart run example/file_streaming/main.dart`

import 'dart:io';
import 'dart:math';

import 'package:pro_mpack/pro_mpack.dart';

void main() async {
  final watch = Stopwatch()..start();
  const fileName = 'market_history_mpack.bin';
  const totalTicks = 1000000;

  log('- File Streaming Example: Real-world File Structure (pro_mpack) -');

  // --- 1. Generation Phase ---
  log('\nGenerating $totalTicks ticks into "$fileName"...');

  final file = File(fileName);
  final ios = file.openWrite();

  final random = Random(42);
  var lastPrice = 50000.0;
  final writeWatch = Stopwatch()..start();

  // Write custom file header (Magic Bytes + Version)
  ios.add([0x4D, 0x4B, 0x54, 0x31, 0x01]); // "MKT1" + v1

  final packer = Packer(initialBufferSize: 64)
    // Pack file metadata as the first MessagePack object
    ..packMap({
      'exchange': 'Binance',
      'symbol': 'BTC/USDT',
      'precision': 2,
      'generated_at': DateTime.now().millisecondsSinceEpoch,
    });

  ios.add(packer.takeBytes());

  final packerStream = Packer(initialBufferSize: 65536);

  // Write streaming data
  for (var i = 0; i < totalTicks; i++) {
    lastPrice += (random.nextDouble() - 0.5) * 10;

    packerStream.packArray([
      DateTime.now().millisecondsSinceEpoch,
      lastPrice,
      random.nextInt(100) + 1,
      random.nextBool(),
    ]);

    // Batch writes to avoid ios.add overhead (approx 64k at a time)
    if (packerStream.bytesWritten >= 64000) {
      ios.add(packerStream.takeBytes(dispose: false));
    }
  }

  // Flush remaining and dispose
  if (packerStream.bytesWritten > 0) {
    ios.add(packerStream.takeBytes());
  }

  writeWatch.stop();
  await ios.close();

  log(
    'File generated. Size: '
    '${(file.lengthSync() / 1024 / 1024).toStringAsFixed(2)} MB, '
    'time: ${writeWatch.elapsedMilliseconds} ms',
  );

  // --- 2. Parsing Phase ---
  log('\nReading and parsing file incrementally...');

  var tickCount = 0;
  var totalVolume = 0;
  var maxPrice = 0.0;
  final readWatch = Stopwatch()..start();
  final mp = MessagePack();

  // Read the first bytes to validate our custom header
  final headerFile = await file.open();
  final magicAndVersion = await headerFile.read(5);

  if (magicAndVersion case [0x4D, 0x4B, 0x54, 0x31, final version]) {
    log('✅ Magic bytes matched (MKT). Version: $version');
  } else {
    log('❌ Invalid Magic Bytes!');
    return;
  }

  // To stream the rest of the file seamlessly, we create a stream from the
  // remaining bytes. We skip the first 5 bytes we just read.
  await headerFile.close();
  final byteStream = file.openRead(5);

  // Pipe the remaining bytes into the zero-allocation streamDecoder
  final tickStream = byteStream.transform(mp.streamDecoder);

  await for (final data in tickStream) {
    switch (data) {
      case Map():
        log('📄 File Metadata: $data');
        continue;

      case [_, final double price, final int volume, _]:
        tickCount++;
        totalVolume += volume;
        if (price > maxPrice) {
          maxPrice = price;
        }

        if (tickCount % 50000 == 0) {
          log('   Processed $tickCount ticks...');
        }

      case _:
        log('⚠️  Unrecognized data format: $data');
    }
  }

  readWatch.stop();

  log('\n✅ Parsing complete!');
  log('Total Ticks: $tickCount');
  log('Total Volume: $totalVolume');
  log('Max Price: \$${maxPrice.toStringAsFixed(2)}');
  log('Read time taken: ${readWatch.elapsedMilliseconds}ms');

  // --- 3. Cleanup ---
  if (file.existsSync()) {
    await file.delete();
    log('\nTemporary file deleted.');
  }

  watch.stop();
  log('Total time taken: ${watch.elapsedMilliseconds}ms');
}

void log([Object? object = '']) => stdout.writeln(object);

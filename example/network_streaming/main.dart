// Network streaming — reconstructing messages from a fragmented byte stream.
//
// Simulates an IoT/telemetry protocol: nested `TelemetryPacket`/`SensorData`
// models are registered as extensions, serialized back-to-back (MessagePack
// is self-framing), then fed through `streamDecoder` in 5-byte chunks to prove
// the zero-allocation transformer reassembles whole objects across chunk
// boundaries.
//
// Run: `dart run example/network_streaming/main.dart`

import 'dart:async';
import 'dart:io';

import 'package:pro_mpack/pro_mpack.dart';

import 'models.dart';

void main() async {
  log('Advanced Streaming Example (pro_mpack)');
  log('Simulating a fragmented network stream using MessagePack...\n');

  // 1. Set up MessagePack with our IoT Extensions
  final mp = MessagePack();
  registerTelemetryExtensions(mp);

  // 2. Prepare some test data
  final packets = [
    TelemetryPacket(
      packetId: 1,
      readings: [
        SensorData(id: 'temp_1', value: 24.5, timestamp: 1622548800000),
        SensorData(id: 'hum_1', value: 45.2, timestamp: 1622548800000),
      ],
    ),
    TelemetryPacket(
      packetId: 2,
      readings: [
        SensorData(id: 'press_1', value: 1013.25, timestamp: 1622548805000),
      ],
    ),
    TelemetryPacket(
      packetId: 3,
      readings: [
        SensorData(id: 'light_1', value: 980.5, timestamp: 1622548810000),
        SensorData(id: 'accel_x', value: -0.05, timestamp: 1622548810000),
        SensorData(id: 'accel_y', value: 0.02, timestamp: 1622548810000),
        SensorData(id: 'accel_z', value: 9.81, timestamp: 1622548810000),
        null,
      ],
    ),
  ];

  // 3. Serialize all packets back-to-back (no custom framing required!)
  // MessagePack formats are self-describing, so they act as their own framing.
  final allBytes = packets.map(mp.pack).expand((b) => b).toList();

  // 4. Create a stream and apply the zero-allocation MessagePack streamDecoder
  final controller = StreamController<List<int>>();
  final telemetryStream = controller.stream.transform(mp.streamDecoder);

  // Listen for parsed packets
  final subscription = telemetryStream.listen((dynamic parsedObject) {
    if (parsedObject is TelemetryPacket) {
      log('✅ Received: $parsedObject');
      for (final reading in parsedObject.readings) {
        log('   -> $reading');
      }
    } else {
      log('⚠️ Received unknown object: $parsedObject');
    }
  });

  // 5. Simulate harsh network fragmentation (sending 5 bytes at a time)
  log('Streaming ${allBytes.length} bytes in 5-byte chunks...');
  const chunkSize = 5;

  for (var i = 0; i < allBytes.length; i += chunkSize) {
    final end = (i + chunkSize < allBytes.length)
        ? i + chunkSize
        : allBytes.length;
    final chunk = allBytes.sublist(i, end);

    log('   [$i] Sending chunk: ${chunk.length} bytes');
    controller.add(chunk);

    // Small delay to simulate network latency
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }

  await controller.close();
  await subscription.asFuture<void>();
  await subscription.cancel();

  log('\nStream closed. All nested IoT packets reconstructed successfully.');
}

void log([Object? object = '']) => stdout.writeln(object);

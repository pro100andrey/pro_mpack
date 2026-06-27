// Models and extension registration for the network streaming example.
//
// `SensorData` and `TelemetryPacket` are registered as standalone extensions;
// a packet packs its readings with `packArray`, so nested `SensorData` values
// (and `null`s) are encoded automatically and decoded with
// `unpackArrayOf<SensorData?>()`.

import 'package:pro_mpack/pro_mpack.dart';

class SensorData {
  SensorData({
    required this.id,
    required this.value,
    required this.timestamp,
  });

  final String id;
  final double value;
  final int timestamp;

  @override
  String toString() => 'SensorData(id: $id, value: $value, ts: $timestamp)';
}

class TelemetryPacket {
  TelemetryPacket({
    required this.packetId,
    required this.readings,
  });

  final int packetId;
  final List<SensorData?> readings;

  @override
  String toString() =>
      'TelemetryPacket(id: $packetId, readings: ${readings.length})';
}

void registerTelemetryExtensions(MessagePack mp) {
  // Register SensorData (Extension ID: 1)
  mp
    ..register(
      extId: 1,
      encoder: (data, packer) {
        packer
          ..packString(data.id)
          ..packDouble(data.value)
          ..packInt(data.timestamp);
      },
      decoder: (unpacker, length) => SensorData(
        id: unpacker.unpackString()!,
        value: unpacker.unpackDouble()!,
        timestamp: unpacker.unpackInt()!,
      ),
    )
    // Register TelemetryPacket (Extension ID: 2)
    ..register(
      extId: 2,
      encoder: (packet, packer) {
        packer
          ..packInt(packet.packetId)
          ..packArray(
            packet.readings,
          ); // SensorData will be automatically encoded!
      },
      decoder: (unpacker, length) {
        final packetId = unpacker.unpackInt()!;

        // We can unpack lists containing custom extensions easily
        final readings = unpacker.unpackArrayOf<SensorData?>();

        return TelemetryPacket(
          packetId: packetId,
          readings: readings,
        );
      },
    );
}

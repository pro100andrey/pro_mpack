// Incremental (field-by-field) codec — the low-level primitives added in 3.1.
//
// A struct is framed as a map of integer field-id → value and written/read one
// field at a time with the typed packers, so no intermediate `Map`/`List` is
// ever built and the generic `pack()` dispatch is bypassed — the shape a
// schema-driven code generator emits. Unknown fields are dropped with
// `Unpacker.skip()`, keeping old readers compatible with newer writers.
//
// Showcases: `packMapLength`/`packArrayLength`, `unpackMapLength`/
// `unpackArrayLength`, `skip()`, and typed `unpackMapOf<K, V>`.
//
// Run: `dart run example/incremental/main.dart`

import 'dart:io';

import 'package:pro_mpack/pro_mpack.dart';

/// A sensor struct, encoded as a map of integer field-id → value.
class Sensor {
  Sensor({
    required this.id,
    required this.label,
    required this.readings,
    this.calibrated = false,
  });

  /// Decodes a struct, skipping any field id this version does not recognise.
  factory Sensor.decode(Unpacker u) {
    var id = 0;
    var label = '';
    var readings = const <double>[];
    var calibrated = false;

    final fieldCount = u.unpackMapLength();
    for (var i = 0; i < fieldCount; i++) {
      switch (u.unpackInt()) {
        case _fId:
          id = u.unpackInt()!;
        case _fLabel:
          label = u.unpackString()!;
        case _fReadings:
          final n = u.unpackArrayLength();
          readings = [for (var j = 0; j < n; j++) u.unpackDouble()!];
        case _fCalibrated:
          calibrated = u.unpackBool()!;
        default:
          u.skip(); // unknown field from a newer writer — stay compatible
      }
    }

    return Sensor(
      id: id,
      label: label,
      readings: readings,
      calibrated: calibrated,
    );
  }

  final int id;
  final String label;
  final List<double> readings;
  final bool calibrated;

  // Stable wire field IDs (never reuse a number).
  static const _fId = 1;
  static const _fLabel = 2;
  static const _fReadings = 3;
  static const _fCalibrated = 4;

  /// Encodes the struct field-by-field — no intermediate `Map` is allocated.
  void encode(Packer p) {
    p
      ..packMapLength(4) // exactly four fields follow
      ..packInt(_fId)
      ..packInt(id)
      ..packInt(_fLabel)
      ..packString(label)
      ..packInt(_fReadings)
      ..packArrayLength(readings.length);

    for (final r in readings) {
      p.packDouble(r);
    }

    p
      ..packInt(_fCalibrated)
      ..packBool(calibrated);
  }

  @override
  String toString() =>
      'Sensor(id: $id, label: $label, readings: $readings, '
      'calibrated: $calibrated)';
}

void main() {
  log('--- Incremental (field-by-field) codec ---');

  final sensor = Sensor(
    id: 7,
    label: 'thermocouple',
    readings: [21.5, 21.7, 22.0],
    calibrated: true,
  );

  // Encode with a bare Packer — zero intermediate Map/List allocation.
  final packer = Packer();
  sensor.encode(packer);
  final bytes = packer.takeBytes();
  log('\nEncoded ${bytes.length} bytes (no intermediate Map built).');

  final decoded = Sensor.decode(Unpacker(buffer: bytes));
  log('Round-trip: $decoded');

  // Forward compatibility: a newer writer adds an unknown field (id 99).
  // The old decoder above skips it via Unpacker.skip().
  log('\n--- Forward compatibility (skip unknown fields) ---');
  final v2 = Packer()
    ..packMapLength(5) // five fields: the four known + one unknown
    ..packInt(Sensor._fId)
    ..packInt(7)
    ..packInt(Sensor._fLabel)
    ..packString('thermocouple')
    ..packInt(Sensor._fReadings)
    ..packArrayLength(1)
    ..packDouble(30.5)
    ..packInt(Sensor._fCalibrated)
    ..packBool(false)
    ..packInt(99) // unknown field id
    ..packString('added-in-a-future-version');

  final fromV2 = Sensor.decode(Unpacker(buffer: v2.takeBytes()));
  log('Decoded v2 payload with old reader: $fromV2');

  // Typed map decode: unpackMapOf<K, V> mirrors unpackArrayOf<T>.
  log('\n--- Typed map decode (unpackMapOf) ---');
  final scoreBytes = serialize({'alice': 10, 'bob': 7});
  final scores = Unpacker(buffer: scoreBytes).unpackMapOf<String, int>();
  log('Typed scores: $scores (${scores.runtimeType})');
}

void log([Object? object = '']) => stdout.writeln(object);

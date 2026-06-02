import 'dart:typed_data';

import 'package:pro_mpack/pro_mpack.dart';
import 'package:test/test.dart';

void main() {
  group('Unpacker Nullable Methods', () {
    test('unpackInt returns null for nil byte', () {
      final u = Unpacker(buffer: Uint8List.fromList([0xc0]));
      expect(u.unpackInt(), isNull);
    });

    test('unpackDouble returns null for nil byte', () {
      final u = Unpacker(buffer: Uint8List.fromList([0xc0]));
      expect(u.unpackDouble(), isNull);
    });

    test('unpackBool returns null for nil byte', () {
      final u = Unpacker(buffer: Uint8List.fromList([0xc0]));
      expect(u.unpackBool(), isNull);
    });

    test('unpackString returns null for nil byte', () {
      final u = Unpacker(buffer: Uint8List.fromList([0xc0]));
      expect(u.unpackString(), isNull);
    });

    test('unpackBinary returns null for nil byte', () {
      final u = Unpacker(buffer: Uint8List.fromList([0xc0]));
      expect(u.unpackBinary(), isNull);
    });

    test('unpackArray returns null for nil byte', () {
      final u = Unpacker(buffer: Uint8List.fromList([0xc0]));
      expect(u.unpackArray(), isNull);
    });

    test('unpackMap returns null for nil byte', () {
      final u = Unpacker(buffer: Uint8List.fromList([0xc0]));
      expect(u.unpackMap(), isNull);
    });
  });

  group('Map orders', () {
    test('preserves map order when true', () {
      final buffer = Uint8List.fromList([
        0x83, // fixmap(3)
        0xa1, 0x7a, 1, // "z": 1
        0xa1, 0x61, 2, // "a": 2
        0xa1, 0x6d, 3, // "m": 3
      ]);
      final result = deserialize(buffer)! as Map;
      expect(result.keys.toList(), ['z', 'a', 'm']);
    });

    test('does not guarantee map order when false (default)', () {
      final buffer = Uint8List.fromList([
        0x83, // fixmap(3)
        0xa1, 0x7a, 1, // "z": 1
        0xa1, 0x61, 2, // "a": 2
        0xa1, 0x6d, 3, // "m": 3
      ]);
      final result = deserialize(buffer)! as Map;
      expect(result, isA<Map<dynamic, dynamic>>());
      expect(result, {
        'z': 1,
        'a': 2,
        'm': 3,
      });
    });

    test('handles duplicate keys by taking the last value', () {
      final buffer = Uint8List.fromList([
        0x82, // fixmap(2)
        0xa1, 0x61, 1, // "a": 1
        0xa1, 0x61, 2, // "a": 2
      ]);

      final resultOrder = deserialize(buffer)! as Map;
      expect(resultOrder['a'], 2);
      expect(resultOrder.length, 1);

      final resultNoOrder = deserialize(buffer)! as Map;
      expect(resultNoOrder['a'], 2);
      expect(resultNoOrder.length, 1);
    });
  });

  group('Unpacker Direct Methods', () {
    test('readBytes reads exact length', () {
      final u = Unpacker(buffer: Uint8List.fromList([1, 2, 3, 4, 5]));
      expect(u.readBytes(3), equals([1, 2, 3]));
      expect(u.offset, 3);
    });

    test('remainingBytes returns unread bytes', () {
      final u = Unpacker(buffer: Uint8List.fromList([1, 2, 3, 4, 5]))
        ..readBytes(2);
      expect(u.remainingBytes, equals([3, 4, 5]));
    });

    test('hasBytesAvailable works correctly', () {
      final u = Unpacker(buffer: Uint8List.fromList([1]));
      expect(u.hasBytesAvailable, isTrue);
      u.readBytes(1);
      expect(u.hasBytesAvailable, isFalse);
    });

    test('rebind resets state to new buffer', () {
      final u = Unpacker(buffer: Uint8List.fromList([1, 2]));
      expect(u.readBytes(1), equals([1]));
      expect(u.offset, 1);

      u.rebind(Uint8List.fromList([3, 4, 5]));
      expect(u.offset, 0);
      expect(u.readBytes(2), equals([3, 4]));
    });

    test('unpackInt success', () {
      final u = Unpacker(buffer: Uint8List.fromList([0x7f]));
      expect(u.unpackInt(), 127);
    });

    test('unpackDouble success', () {
      final u = Unpacker(
        buffer: Uint8List.fromList([
          0xcb,
          0x40,
          0x09,
          0x21,
          0xFB,
          0x54,
          0x44,
          0x2D,
          0x18,
        ]),
      );
      expect(u.unpackDouble(), 3.141592653589793);
    });

    test('unpackBool success', () {
      final u = Unpacker(buffer: Uint8List.fromList([0xc3]));
      expect(u.unpackBool(), isTrue);
    });

    test('unpackString success', () {
      final u = Unpacker(
        buffer: Uint8List.fromList([0xa3, ...'foo'.codeUnits]),
      );
      expect(u.unpackString(), 'foo');
    });

    test('unpackBinary success', () {
      final u = Unpacker(buffer: Uint8List.fromList([0xc4, 3, 1, 2, 3]));
      expect(u.unpackBinary(), equals([1, 2, 3]));
    });

    test('unpackArray success', () {
      final u = Unpacker(buffer: Uint8List.fromList([0x93, 1, 2, 3]));
      expect(u.unpackArray(), equals([1, 2, 3]));
    });

    test('unpackMap success', () {
      final u = Unpacker(buffer: Uint8List.fromList([0x81, 0xa1, 0x61, 1]));
      expect(u.unpackMap(), equals({'a': 1}));
    });

    test('unpackTimestamp success', () {
      final u = Unpacker(
        buffer: Uint8List.fromList([0xd6, 0xff, 0x00, 0x00, 0x00, 0x01]),
      );
      expect(u.unpackTimestamp(), equals(DateTime.utc(1970, 1, 1, 0, 0, 1)));
    });

    test('unpackAs success', () {
      final u = Unpacker(
        buffer: Uint8List.fromList([0xa3, ...'foo'.codeUnits]),
      );
      expect(u.unpackAs<String>(), 'foo');
    });

    test('unpackAs throws TypeError on mismatch', () {
      final u = Unpacker(
        buffer: Uint8List.fromList([0xa3, ...'foo'.codeUnits]),
      );
      expect(() => u.unpackAs<int>(), throwsA(isA<TypeError>()));
    });
  });
}

import 'dart:typed_data';

import 'package:pro_mpack/pro_mpack.dart';
import 'package:test/test.dart';

void main() {
  group('Spec Compliance - Timestamp', () {
    test('TS32: 1970-01-01 00:00:01 (sec=1, nano=0)', () {
      final date = DateTime.utc(1970, 1, 1, 0, 0, 1);
      final encoded = serialize(date);
      // expect fixext 4, type -1, 4 bytes of seconds
      expect(encoded, Uint8List.fromList([0xd6, 0xff, 0x00, 0x00, 0x00, 0x01]));
      expect(deserialize(encoded), date);
    });

    test('TS64: 1970-01-01 00:00:01 with 1 microsecond (sec=1, nano=1000)', () {
      final date = DateTime.utc(1970, 1, 1, 0, 0, 1, 0, 1);
      final encoded = serialize(date);
      // expect fixext 8, type -1, 8 bytes: [nano 30b][sec 34b]
      // nano = 1000 (0x3E8)
      // sec = 1
      // high32 = (1000 << 2) | (1 ~/ 2^32) = 4000 (0xFA0) | 0 = 0xFA0
      // low32 = 1 & 0xFFFFFFFF = 1
      // Payload: 00 00 0F A0 00 00 00 01
      expect(
        encoded,
        Uint8List.fromList([
          0xd7,
          0xff,
          0x00,
          0x00,
          0x0f,
          0xa0,
          0x00,
          0x00,
          0x00,
          0x01,
        ]),
      );
      expect(deserialize(encoded), date);
    });

    test('TS64: Current date (approx 2024)', () {
      final date = DateTime.utc(2024, 1, 1, 12, 34, 56, 789, 123);
      final encoded = serialize(date);
      expect(deserialize(encoded), date);
    });

    test('TS64: Max 64-bit TS (year 2514)', () {
      // 2^34 - 1 seconds from 1970 is 17179869183
      const maxSecs = 17179869183;
      final date = DateTime.fromMicrosecondsSinceEpoch(
        maxSecs * 1000000 + 999000, // 999ms
        isUtc: true,
      );
      final encoded = serialize(date);
      expect(encoded[0], 0xd7); // Must be fixext 8
      expect(deserialize(encoded), date);
    });

    test('TS96: Negative timestamp (pre-1970)', () {
      final date = DateTime.utc(1960);
      final encoded = serialize(date);
      // Expect ext 8 (0xc7) + 12 bytes + type -1
      expect(encoded[0], 0xc7);
      expect(encoded[1], 12);
      expect(encoded[2], 255); // -1 as uint8

      final decoded = deserialize(encoded);
      expect(decoded, date);
    });

    test('TS96: Nanoseconds precision', () {
      final date = DateTime.utc(2000, 1, 1, 0, 0, 0, 0, 1); // 1 microsecond
      // Nanoseconds are micros * 1000
      final encoded = serialize(date);
      final decoded = deserialize(encoded);
      expect(decoded, date);
    });

    test('TS96: Far future (year 3000)', () {
      final date = DateTime.utc(3000);
      final encoded = serialize(date);
      expect(encoded[0], 0xc7); // ext 8
      expect(deserialize(encoded), date);
    });
  });

  group('Spec Compliance - Integer Boundaries', () {
    test('Int boundary: -32 (fixint) vs -33 (int8)', () {
      expect(serialize(-32)[0], 0xe0);
      expect(serialize(-33)[0], 0xd0);
    });

    test('Int boundary: -128 (int8) vs -129 (int16)', () {
      // -128 is 0x80 signed (or 0x80 as uint8 with d0 prefix)
      expect(serialize(-128)[0], 0xd0);
      expect(serialize(-129)[0], 0xd1);
    });

    test('Int boundary: -32768 (int16) vs -32769 (int32)', () {
      expect(serialize(-32768)[0], 0xd1);
      expect(serialize(-32769)[0], 0xd2);
    });

    test('Int boundary: -2147483648 (int32) vs -2147483649 (int64)', () {
      expect(serialize(-2147483648)[0], 0xd2);
      expect(serialize(-2147483649)[0], 0xd3);
    });

    test('Int boundary: 127 (fixint) vs 128 (uint8)', () {
      expect(serialize(127)[0], 0x7f);
      expect(serialize(128)[0], 0xcc);
    });

    test('Int boundary: 255 (uint8) vs 256 (uint16)', () {
      expect(serialize(255)[0], 0xcc);
      expect(serialize(256)[0], 0xcd);
    });

    test('Int boundary: 65535 (uint16) vs 65536 (uint32)', () {
      expect(serialize(65535)[0], 0xcd);
      expect(serialize(65536)[0], 0xce);
    });

    test('Int boundary: 4294967295 (uint32) vs 4294967296 (uint64)', () {
      expect(serialize(4294967295)[0], 0xce);
      expect(serialize(4294967296)[0], 0xcf);
    });
  });

  group('Spec Compliance - Variable Length Boundaries', () {
    // Helper to generate string of length N
    String s(int n) => 'a' * n;
    // Helper to generate bytes of length N
    Uint8List b(int n) => Uint8List(n);
    // Helper to generate list of length N
    List<int> l(int n) => List.filled(n, 0);
    // Helper to generate map of length N
    Map<int, int> m(int n) => Map.fromIterables(
      List.generate(n, (i) => i),
      List.generate(n, (i) => i),
    );

    test('String boundary: 31 (fixstr) vs 32 (str8)', () {
      expect(serialize(s(31))[0] & 0xe0, 0xa0); // fixstr prefix
      expect(serialize(s(32))[0], 0xd9); // str8
    });

    test('String boundary: 255 (str8) vs 256 (str16)', () {
      expect(serialize(s(255))[0], 0xd9);
      expect(serialize(s(256))[0], 0xda);
    });

    test('String boundary: 65535 (str16) vs 65536 (str32)', () {
      expect(serialize(s(65535))[0], 0xda);
      expect(serialize(s(65536))[0], 0xdb);
    });

    test('Binary boundary: 255 (bin8) vs 256 (bin16)', () {
      expect(serialize(b(255))[0], 0xc4);
      expect(serialize(b(256))[0], 0xc5);
    });

    test('Binary boundary: 65535 (bin16) vs 65536 (bin32)', () {
      expect(serialize(b(65535))[0], 0xc5);
      expect(serialize(b(65536))[0], 0xc6);
    });

    test('Array boundary: 15 (fixarray) vs 16 (array16)', () {
      expect(serialize(l(15))[0] & 0xf0, 0x90); // fixarray prefix
      expect(serialize(l(16))[0], 0xdc); // array16
    });

    test('Array boundary: 65535 (array16) vs 65536 (array32)', () {
      expect(serialize(l(65535))[0], 0xdc);
      expect(serialize(l(65536))[0], 0xdd);
    });

    test('Map boundary: 15 (fixmap) vs 16 (map16)', () {
      expect(serialize(m(15))[0] & 0xf0, 0x80); // fixmap prefix
      expect(serialize(m(16))[0], 0xde); // map16
    });

    test('Map boundary: 65535 (map16) vs 65536 (map32)', () {
      expect(serialize(m(65535))[0], 0xde);
      expect(serialize(m(65536))[0], 0xdf);
    });
  });
}

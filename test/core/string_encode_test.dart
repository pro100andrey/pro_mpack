import 'dart:convert';

import 'package:pro_mpack/pro_mpack.dart';
import 'package:pro_mpack/src/core/constants.dart';
import 'package:test/test.dart';

void main() {
  group('single-pass string encode', () {
    /// Every string header boundary, by UTF-8 byte length (ASCII → 1 byte/char).
    for (final len in [0, 1, 31, 32, 255, 256, 65535, 65536]) {
      test('ASCII length $len: correct header + round-trip', () {
        final s = 'a' * len;
        final bytes = serialize(s);
        expect(utf8.encode(s).length, len);

        if (len <= 31) {
          expect(bytes[0], fFixStrPrefix | len);
        } else if (len <= limitUint8) {
          expect(bytes[0], fStr8);
          expect(bytes[1], len);
        } else if (len <= limitUint16) {
          expect(bytes[0], fStr16);
          expect((bytes[1] << 8) | bytes[2], len);
        } else {
          expect(bytes[0], fStr32);
          expect(
            (bytes[1] << 24) | (bytes[2] << 16) | (bytes[3] << 8) | bytes[4],
            len,
          );
        }

        expect(deserialize(bytes), s);
      });
    }

    test('multi-byte UTF-8 round-trips (2/3/4-byte sequences)', () {
      const samples = [
        'héllo wörld', // 2-byte (Latin-1 supplement)
        'Привет мир', // 2-byte (Cyrillic)
        '中文字符串', // 3-byte (CJK)
        '😀🌍🎉', // 4-byte (surrogate pairs)
        'mixed: a é 中 😀 z', // all widths in one string
      ];

      for (final s in samples) {
        final bytes = serialize(s);
        // Header length field must equal the UTF-8 byte length, not char count.
        expect(deserialize(bytes), s, reason: s);
      }
    });

    test('byte length crossing a boundary via multi-byte chars', () {
      // 20 × 3-byte chars = 60 bytes → still fixstr is impossible (>31) → str8.
      final s = '中' * 20;
      expect(utf8.encode(s).length, 60);
      final bytes = serialize(s);
      expect(bytes[0], fStr8);
      expect(bytes[1], 60);
      expect(deserialize(bytes), s);
    });

    test('lone surrogate is replaced with U+FFFD (allowMalformed)', () {
      final bytes = serialize('\uD800'); // high surrogate with no low
      expect(deserialize(bytes), '�');
    });
  });
}

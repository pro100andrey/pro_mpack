import 'dart:typed_data';

import 'package:pro_mpack/pro_mpack.dart';
import 'package:test/test.dart';

void main() {
  group('packArrayLength / unpackArrayLength', () {
    for (final n in [0, 1, 15, 16, 65535, 65536]) {
      test('header + elements is byte-identical to packArray ($n)', () {
        final list = List<int>.generate(n, (i) => i % 128);

        final p = Packer()..packArrayLength(list.length);
        for (final v in list) {
          p.packInt(v);
        }
        expect(p.takeBytes(), equals(serialize(list)));
      });

      test('unpackArrayLength + reads matches unpackArray ($n)', () {
        final list = List<int>.generate(n, (i) => i % 128);
        final u = Unpacker(buffer: serialize(list));

        final len = u.unpackArrayLength();
        expect(len, n);

        final out = List<int>.generate(len, (_) => u.unpackInt()!);
        expect(out, list);
        expect(u.hasBytesAvailable, isFalse);
      });
    }

    test('unpackArrayLength throws on a non-array header', () {
      final u = Unpacker(buffer: serialize('not an array'));
      expect(u.unpackArrayLength, throwsA(isA<MessagePackFormatException>()));
    });
  });

  group('packMapLength / unpackMapLength', () {
    for (final n in [0, 1, 15, 16, 65535, 65536]) {
      test('header + entries is byte-identical to packMap ($n)', () {
        final map = {for (var i = 0; i < n; i++) i % 128: (i % 128) + 1};

        final p = Packer()..packMapLength(map.length);
        map.forEach((k, v) {
          p
            ..packInt(k)
            ..packInt(v);
        });
        expect(p.takeBytes(), equals(serialize(map)));
      });

      test('unpackMapLength + reads matches unpackMap ($n)', () {
        final map = {for (var i = 0; i < n; i++) i % 128: (i % 128) + 1};
        final u = Unpacker(buffer: serialize(map));

        final len = u.unpackMapLength();
        expect(len, map.length);

        final out = <int, int>{};
        for (var i = 0; i < len; i++) {
          out[u.unpackInt()!] = u.unpackInt()!;
        }
        expect(out, map);
        expect(u.hasBytesAvailable, isFalse);
      });
    }

    test('unpackMapLength throws on a non-map header', () {
      final u = Unpacker(buffer: serialize([1, 2, 3]));
      expect(u.unpackMapLength, throwsA(isA<MessagePackFormatException>()));
    });
  });

  group('Unpacker.skip advances by exactly bytes(value)', () {
    /// One named sample per value kind. `bytes` is its full encoding.
    final samples = <String, Uint8List>{
      'nil': serialize(null),
      'bool true': serialize(true),
      'fixint': serialize(7),
      'negative fixint': serialize(-1),
      'uint8': serialize(200),
      'uint16': serialize(40000),
      'uint32': serialize(0x7FFFFFFF + 10),
      'int8': serialize(-100),
      'int16': serialize(-30000),
      'int32': serialize(-2000000000),
      'float32': serialize(Float(1.5)),
      'float64': serialize(3.14159),
      'fixstr': serialize('hi'),
      'str8': serialize('a' * 100),
      'str16': serialize('b' * 1000),
      'bin8': serialize(Uint8List.fromList(List.filled(20, 1))),
      'fixarray': serialize([1, 2, 3]),
      'array16': serialize(List<int>.filled(50, 9)),
      'fixmap': serialize({1: 2, 3: 4}),
      'map16': serialize({for (var i = 0; i < 50; i++) i: i}),
      'timestamp TS32': serialize(
        DateTime.fromMillisecondsSinceEpoch(1000000000 * 1000, isUtc: true),
      ),
      'timestamp TS96': serialize(
        DateTime.utc(1500),
      ),
      'nested': serialize([
        1,
        [2, 3],
        {4: 5},
        'x',
      ]),
    };

    for (final MapEntry(key: label, value: bytes) in samples.entries) {
      test('skip over $label', () {
        // Append a sentinel to confirm the reader lands on the next value.
        final sentinel = serialize(0x2A);
        final buf = Uint8List.fromList([...bytes, ...sentinel]);

        final u = Unpacker(buffer: buf)..skip();

        expect(u.offset, bytes.length, reason: 'advanced exactly $label');
        expect(u.unpack(), 0x2A);
        expect(u.hasBytesAvailable, isFalse);
      });
    }

    test('skip over a raw ext8 extension', () {
      final p = Packer()
        ..packRawExtension(7, Uint8List.fromList(List.filled(20, 3)));
      final bytes = p.takeBytes();

      final buf = Uint8List.fromList([...bytes, ...serialize(99)]);
      final u = Unpacker(buffer: buf)..skip();

      expect(u.offset, bytes.length);
      expect(u.unpack(), 99);
    });

    test('skip throws on the reserved 0xc1 byte', () {
      final u = Unpacker(buffer: Uint8List.fromList([0xc1]));
      expect(u.skip, throwsA(isA<MessagePackFormatException>()));
    });
  });

  group('Unpacker.unpackMapOf<K, V>', () {
    test('returns a typed map with the same entries as unpackMap', () {
      const map = {'a': 1, 'b': 2, 'c': 3};
      final out = Unpacker(buffer: serialize(map)).unpackMapOf<String, int>();

      expect(out, isA<Map<String, int>>());
      expect(out, map);
    });

    test('throws on a nil map (non-nullable, like unpackArrayOf)', () {
      final u = Unpacker(buffer: serialize(null));
      expect(u.unpackMapOf<String, int>, throwsA(anything));
    });
  });
}

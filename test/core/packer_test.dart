import 'dart:typed_data';

import 'package:pro_mpack/pro_mpack.dart';
import 'package:test/test.dart';

class _MockInvalidTypeEncoder {
  bool call(Object? value, Packer p) {
    p.packExt(200, (p) {});
    return true;
  }
}

class _MockSuccessEncoder {
  bool call(Object? value, Packer p) {
    p.packExt(10, (p) {
      p.packInt(0);
    });
    return true;
  }
}

void main() {
  group('Packer Alias Methods', () {
    test('packBool delegates correctly', () {
      final p1 = Packer();
      final p2 = Packer();
      p1.pack(true);
      p2.packBool(true);
      expect(p2.takeBytes(), equals(p1.takeBytes()));
    });

    test('packInt delegates correctly', () {
      final p1 = Packer();
      final p2 = Packer();
      p1.pack(42);
      p2.packInt(42);
      expect(p2.takeBytes(), equals(p1.takeBytes()));
    });

    test('packFloat delegates correctly', () {
      final p1 = Packer();
      final p2 = Packer();
      p1.pack(Float(3.14));
      p2.packFloat(Float(3.14));
      expect(p2.takeBytes(), equals(p1.takeBytes()));
    });

    test('packDouble delegates correctly', () {
      final p1 = Packer();
      final p2 = Packer();
      p1.pack(3.14);
      p2.packDouble(3.14);
      expect(p2.takeBytes(), equals(p1.takeBytes()));
    });

    test('packString delegates correctly', () {
      final p1 = Packer();
      final p2 = Packer();
      p1.pack('hello');
      p2.packString('hello');
      expect(p2.takeBytes(), equals(p1.takeBytes()));
    });

    test('packBinary delegates correctly', () {
      final p1 = Packer();
      final p2 = Packer();
      final data = Uint8List.fromList([1, 2, 3]);
      p1.pack(data);
      p2.packBinary(data);
      expect(p2.takeBytes(), equals(p1.takeBytes()));
    });

    test('packArray delegates correctly', () {
      final p1 = Packer();
      final p2 = Packer();
      final data = [1, 2, 3];
      p1.pack(data);
      p2.packArray(data);
      expect(p2.takeBytes(), equals(p1.takeBytes()));
    });

    test('packMap delegates correctly', () {
      final p1 = Packer();
      final p2 = Packer();
      final data = {'a': 1};
      p1.pack(data);
      p2.packMap(data);
      expect(p2.takeBytes(), equals(p1.takeBytes()));
    });

    test('packTimestamp delegates correctly', () {
      final p1 = Packer();
      final p2 = Packer();
      final date = DateTime.utc(2020);
      p1.pack(date);
      p2.packTimestamp(date);
      expect(p2.takeBytes(), equals(p1.takeBytes()));
    });

    test('aliases handle null correctly', () {
      final p = Packer()
        ..packBool(null)
        ..packInt(null)
        ..packString(null);
      expect(p.takeBytes(), equals([0xc0, 0xc0, 0xc0]));
    });

    test('appendRaw appends bytes correctly', () {
      final p = Packer()..appendRaw(Uint8List.fromList([1, 2, 3]));
      expect(p.takeBytes(), equals([1, 2, 3]));
    });

    test('packRawExtension writes correct ext format', () {
      final p = Packer()..packRawExtension(10, Uint8List.fromList([42]));
      expect(p.takeBytes(), equals([0xd4, 10, 42]));
    });
  });

  group('Serializer Edge Cases', () {
    test('Iterable is not List', () {
      final s = Packer()..pack({1, 2, 3}); // Set is Iterable but not List
      final bytes = s.takeBytes();
      final d = Unpacker(buffer: bytes);
      expect(d.unpack(), [1, 2, 3]);
    });

    test('encodeExt returns null for unsupported type', () {
      final s = Packer(); // No encodeExt
      expect(
        () => s.pack(Object()),
        throwsA(
          isA<MessagePackUnsupportedTypeException>().having(
            (e) => e.message,
            'message',
            contains("Don't know how to serialize type"),
          ),
        ),
      );
    });

    test('encodeExt returns invalid type range', () {
      final s = Packer(encodeExt: _MockInvalidTypeEncoder().call);
      expect(
        () => s.pack(Object()),
        throwsA(
          isA<MessagePackConfigurationException>().having(
            (e) => e.message,
            'message',
            contains('Type must be in the range'),
          ),
        ),
      );
    });

    test('packRawExtension success path in encode', () {
      final s = Packer(encodeExt: _MockSuccessEncoder().call)..pack(Object());
      final bytes = s.takeBytes();
      expect(bytes, [0xd4, 0x0a, 0x00]);
    });

    test('explicit dispose can be called without error', () {
      Packer()
        ..pack(42)
        ..dispose();
      // Test passes if no exception is thrown
    });
  });

  group('Float', () {
    test('Float toString', () {
      expect(Float(1.2).toString(), 'Float(1.2)');
    });
  });
}

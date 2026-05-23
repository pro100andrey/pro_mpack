import 'dart:typed_data';

import 'package:pro_mpack/pro_mpack.dart';
import 'package:test/test.dart';

import 'utils/utils.dart';

void main() {
  // Type system tests

  // Nil format
  test('serializes nil format correctly', () {
    final result = serialize(null);
    expect(result, Uint8List.fromList([0xc0 /* nil */]));
  });

  // Boolean formats
  test('serializes false format correctly', () {
    final result = serialize(false);
    expect(result, Uint8List.fromList([0xc2 /* false */]));
  });

  test('serializes true format correctly', () {
    final result = serialize(true);
    expect(result, Uint8List.fromList([0xc3 /* true */]));
  });

  // Integer formats
  test('serializes positive fixint correctly', () {
    final result = serialize(127);
    expect(result, Uint8List.fromList([0x7f /* 127 */]));
  });

  test('serializes negative fixint correctly', () {
    final result = serialize(-32);
    expect(result, Uint8List.fromList([0xe0 /* -32 */]));
  });

  test('serializes uint 8 format correctly', () {
    final result = serialize(128);
    expect(result, Uint8List.fromList([0xcc /* uint 8 */, 0x80])); // 128
  });

  test('serializes uint 16 format correctly', () {
    final result = serialize(256);
    expect(result, Uint8List.fromList([0xcd /* uint 16 */, 0x01, 0x00])); // 256
  });

  test('serializes uint 32 format correctly', () {
    final result = serialize(65536);
    expect(
      result,
      Uint8List.fromList(
        [0xce /* uint 32 */, 0x00, 0x01, 0x00, 0x00],
      ),
    ); // 65536
  });

  test('serializes uint 64 format correctly', () {
    final result = serialize(4294967296);
    expect(
      result,
      Uint8List.fromList([
        0xcf /* uint 64 */,
        0x00,
        0x00,
        0x00,
        0x01,
        0x00,
        0x00,
        0x00,
        0x00,
      ]),
    ); // 4294967296
  });

  test('serializes int 8 format correctly', () {
    final result = serialize(-48);
    expect(result, Uint8List.fromList([0xd0 /* int 8 */, 0xd0])); // -48
  });

  test('serializes int 16 format correctly', () {
    final result = serialize(-32768);
    expect(
      result,
      Uint8List.fromList([0xd1 /* int 16 */, 0x80, 0x00]),
    ); // -32768
  });

  test('serializes int 32 format correctly', () {
    final result = serialize(-2147483648);
    expect(
      result,
      Uint8List.fromList([0xd2 /* int 32 */, 0x80, 0x00, 0x00, 0x00]),
    ); // -2147483648
  });

  test('serializes min int 64 format correctly', () {
    final result = serialize(-9223372036854775808);
    expect(
      result,
      Uint8List.fromList([
        0xd3 /* int 64 */,
        0x80,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
      ]),
    ); // -9223372036854775808
  });

  // Float formats
  test('serializes float 32 format correctly', () {
    final result = serialize(Float(3.1415927));
    expect(
      result,
      Uint8List.fromList(
        [0xca /* float 32 */, 0x40, 0x49, 0x0f, 0xdb],
      ),
    ); // 3.1415927
  });

  test('serializes float 64 format correctly', () {
    final result = serialize(3.141592653589793);
    expect(
      result,
      Uint8List.fromList([
        0xcb /* float 64 */,
        0x40,
        0x09,
        0x21,
        0xfb,
        0x54,
        0x44,
        0x2d,
        0x18,
      ]),
    ); // 3.141592653589793
  });

  // String formats
  test('serializes fixstr format correctly', () {
    final result = serialize('hello');
    expect(
      result,
      Uint8List.fromList(
        [0xa5 /* fixstr (5) */, 0x68, 0x65, 0x6c, 0x6c, 0x6f],
      ),
    ); // "hello"
  });

  test('serializes str 8 format correctly', () {
    final longString = 'a' * 32; // Длина строки 32 символа
    final result = serialize(longString);
    expect(
      result,
      Uint8List.fromList(
        [0xd9 /* str 8 */, 32, ...List.filled(32, 0x61)],
      ),
    ); // "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  });

  test('serializes str 16 format correctly', () {
    final longString = 'a' * 256; // Длина строки 256 символов
    final result = serialize(longString);
    expect(
      result,
      Uint8List.fromList(
        [0xda /* str 16 */, 0x01, 0x00, ...List.filled(256, 0x61)],
      ),
    ); // 256 'a's
  });

  test('serializes str 32 format correctly', () {
    final longString = 'a' * 70000; // Длина строки 70000 символов
    final result = serialize(longString);
    expect(
      result,
      Uint8List.fromList([
        0xdb /* str 32 */,
        0x00, 0x01, 0x11, 0x70, // Длина строки 70000 в формате big-endian
        ...List.filled(70000, 0x61),
      ]),
    ); // 70000 'a's
  });

  // Binary formats
  test('serializes bin 8 format correctly', () {
    final result = serialize(Uint8List.fromList([1, 2, 3]));
    expect(
      result,
      Uint8List.fromList([0xc4 /* bin 8 */, 3, 1, 2, 3]),
    ); // [1, 2, 3]
  });

  test('serializes bin 16 format correctly', () {
    final result = serialize(Uint8List.fromList(List.filled(256, 0x61)));
    expect(
      result,
      Uint8List.fromList([
        0xc5 /* bin 16 */,
        0x01,
        0x00,
        ...List.filled(256, 0x61),
      ]),
    ); // 256 'a's
  });

  test('serializes bin 32 format correctly', () {
    final result = serialize(Uint8List.fromList(List.filled(65536, 0x61)));
    expect(
      result,
      Uint8List.fromList([
        0xc6 /* bin 32 */,
        0x00,
        0x01,
        0x00,
        0x00,
        ...List.filled(65536, 0x61),
      ]),
    ); // 65536 'a's
  });

  // Array formats
  test('serializes fixarray format correctly', () {
    final result = serialize([1, 2, 3]);
    expect(
      result,
      Uint8List.fromList([0x93 /* fixarray (3) */, 1, 2, 3]),
    ); // [1, 2, 3]
  });

  test('serializes array 16 format correctly', () {
    final result = serialize(List.filled(256, 0x01));
    expect(
      result,
      Uint8List.fromList(
        [0xdc /* array 16 */, 0x01, 0x00, ...List.filled(256, 0x01)],
      ),
    ); // [1, 1, 1, ..., 1] (256 times)
  });

  test('serializes array 32 format correctly', () {
    final result = serialize(List.filled(65536, 0x01));
    expect(
      result.sublist(0, 5),
      Uint8List.fromList([
        0xdd /* array 32 */,
        0x00,
        0x01,
        0x00,
        0x00,
      ]),
    ); // List with 65536 elements
  });

  // Map formats
  test('serializes fixmap format correctly', () {
    final result = serialize({'key': 'value'});
    expect(
      result,
      Uint8List.fromList([
        0x81 /* fixmap (1) */,
        0xa3,
        0x6b,
        0x65,
        0x79,
        0xa5,
        0x76,
        0x61,
        0x6c,
        0x75,
        0x65,
      ]),
    ); // {"key": "value"}
  });

  test('serializes map 16 format correctly', () {
    final result = serialize(
      Map.fromIterables(
        List.generate(256, (i) => i),
        List.generate(256, (i) => i),
      ),
    );
    expect(
      result.sublist(0, 3),
      Uint8List.fromList(
        [0xde /* map 16 */, 0x01, 0x00],
      ),
    ); // Map with 256 elements
  });

  test('serializes map 32 format correctly', () {
    final result = serialize(
      Map.fromIterables(
        List.generate(65536, (i) => i),
        List.generate(65536, (i) => i),
      ),
    );
    expect(
      result.sublist(0, 5),
      Uint8List.fromList([
        0xdf /* map 32 */,
        0x00,
        0x01,
        0x00,
        0x00,
      ]),
    ); // Map with 65536 elements
  });

  // Extension formats
  test('serializes fixext 1 format correctly', () {
    final extEncoder = TestExtEncoder();
    final result = serialize(
      CustomExtension(1, Uint8List.fromList([42])),
      extEncoder: extEncoder,
    );
    expect(result, Uint8List.fromList([0xd4 /* fixext 1 */, 1, 42]));
  });

  test('serializes fixext 2 format correctly', () {
    final extEncoder = TestExtEncoder();
    final result = serialize(
      CustomExtension(2, Uint8List.fromList([42, 43])),
      extEncoder: extEncoder,
    );
    expect(result, Uint8List.fromList([0xd5 /* fixext 2 */, 2, 42, 43]));
  });

  test('serializes fixext 4 format correctly', () {
    final extEncoder = TestExtEncoder();
    final result = serialize(
      CustomExtension(3, Uint8List.fromList([42, 43, 44, 45])),
      extEncoder: extEncoder,
    );
    expect(
      result,
      Uint8List.fromList([0xd6 /* fixext 4 */, 3, 42, 43, 44, 45]),
    );
  });

  test('serializes fixext 8 format correctly', () {
    final extEncoder = TestExtEncoder();
    final result = serialize(
      CustomExtension(
        4,
        Uint8List.fromList([42, 43, 44, 45, 46, 47, 48, 49]),
      ),
      extEncoder: extEncoder,
    );
    expect(
      result,
      Uint8List.fromList(
        [0xd7 /* fixext 8 */, 4, 42, 43, 44, 45, 46, 47, 48, 49],
      ),
    );
  });

  test('serializes fixext 16 format correctly', () {
    final extEncoder = TestExtEncoder();
    final result = serialize(
      CustomExtension(
        5,
        Uint8List.fromList([
          42,
          43,
          44,
          45,
          46,
          47,
          48,
          49,
          50,
          51,
          52,
          53,
          54,
          55,
          56,
          57,
        ]),
      ),
      extEncoder: extEncoder,
    );
    expect(
      result,
      Uint8List.fromList([
        0xd8 /* fixext 16 */,
        5, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, //
      ]),
    );
  });
  // Тесты для timestamp
  test('serializes timestamp 32 format correctly', () {
    final timestamp = DateTime.utc(1970, 1, 1, 0, 0, 1);
    final result = serialize(timestamp);
    expect(
      result,
      Uint8List.fromList([0xd6 /* fixext 4 */, -1, 0x00, 0x00, 0x00, 0x01]),
    );
  });

  test('serializes timestamp 64 format correctly', () {
    final timestamp = DateTime.utc(1970, 1, 1, 0, 0, 1, 0, 2);
    final result = serialize(timestamp);
    expect(
      result,
      Uint8List.fromList([
        0xd7 /* fixext 8 */,
        -1,
        0x00,
        0x00,
        0x1f,
        0x40,
        0x00,
        0x00,
        0x00,
        0x01,
      ]),
    );
  });

  test(
    'throws MessagePackUnsupportedTypeException '
    'when serializing unsupported object',
    () {
      expect(
        () => serialize(Object()),
        throwsA(isA<MessagePackUnsupportedTypeException>()),
      );
    },
  );

  test('serializes int beyond fixint range correctly', () {
    final result = serialize(-33);
    expect(result, Uint8List.fromList([0xd0, 0xdf]));
  });

  test('serializes large uint 64 value correctly', () {
    final result = serialize(9223372036854775807);
    expect(
      result,
      Uint8List.fromList(
        [0xcf, 0x7f, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff],
      ),
    );
  });

  test(
    'throws MessagePackUnsupportedTypeException for unsupported ext type',
    () {
      final extEncoder = TestExtEncoder();
      expect(
        () => serialize(RegExp(''), extEncoder: extEncoder),
        throwsA(isA<MessagePackUnsupportedTypeException>()),
      );
    },
  );

  test('serializes array with complex objects correctly', () {
    final result = serialize([Float(3.14), 256, true]);

    expect(
      result,
      Uint8List.fromList([
        0x93, // fixarray (3)
        0xca, 0x40, 0x48, 0xf5, 0xc3, // Float(3.14)
        0xcd, 0x01, 0x00, // uint16 (256)
        0xc3, // true
      ]),
    );
  });

  test('serializes map with non-string keys correctly', () {
    final result = serialize({1: 'one', 2: 'two'});

    expect(
      result,
      Uint8List.fromList([
        0x82, // fixmap (2)
        0x01, // int 1
        0xa3, 0x6f, 0x6e, 0x65, // "one"
        0x02, // int 2
        0xa3, 0x74, 0x77, 0x6f, // "two"
      ]),
    );
  });

  test('serializes empty map correctly', () {
    final result = serialize({});
    expect(result, Uint8List.fromList([0x80]));
  });

  // Extension format tests (ext 8, ext 16, ext 32)
  test('serializes ext 8 format correctly', () {
    final extEncoder = TestExtEncoder();
    final data = Uint8List.fromList(List.filled(32, 42));
    final result = serialize(
      CustomExtension(10, data),
      extEncoder: extEncoder,
    );
    expect(
      result.sublist(0, 3),
      Uint8List.fromList([0xc7 /* ext 8 */, 32, 10]),
    );
  });

  test('serializes ext 16 format correctly', () {
    final extEncoder = TestExtEncoder();
    final data = Uint8List.fromList(List.filled(256, 42));
    final result = serialize(
      CustomExtension(11, data),
      extEncoder: extEncoder,
    );
    expect(
      result.sublist(0, 4),
      Uint8List.fromList([0xc8 /* ext 16 */, 0x01, 0x00, 11]),
    );
  });

  test('serializes ext 32 format correctly', () {
    final extEncoder = TestExtEncoder();
    final data = Uint8List.fromList(List.filled(70000, 42));
    final result = serialize(
      CustomExtension(12, data),
      extEncoder: extEncoder,
    );
    expect(
      result.sublist(0, 6),
      Uint8List.fromList([0xc9 /* ext 32 */, 0x00, 0x01, 0x11, 0x70, 12]),
    );
  });

  // Edge case tests
  test('serializes empty array correctly', () {
    final result = serialize([]);
    expect(result, Uint8List.fromList([0x90]));
  });

  test('serializes empty binary correctly', () {
    final result = serialize(Uint8List(0));
    expect(result, Uint8List.fromList([0xc4, 0]));
  });

  test('serializes empty string correctly', () {
    final result = serialize('');
    expect(result, Uint8List.fromList([0xa0]));
  });

  test('serializes zero correctly', () {
    final result = serialize(0);
    expect(result, Uint8List.fromList([0x00]));
  });

  // Nested structure tests
  test('serializes nested array correctly', () {
    final result = serialize([
      [1],
      2,
    ]);
    expect(
      result,
      Uint8List.fromList(
        [0x92 /* fixarray(2) */, 0x91 /* fixarray(1) */, 1, 2],
      ),
    );
  });

  test('serializes nested map correctly', () {
    final result = serialize({
      'a': {'b': 1},
    });
    expect(
      result,
      Uint8List.fromList([
        0x81 /* fixmap(1) */,
        0xa1,
        0x61, // "a"
        0x81 /* fixmap(1) */,
        0xa1,
        0x62, // "b"
        1,
      ]),
    );
  });

  // Boundary tests
  test('serializes fixstr to str 8 boundary correctly', () {
    final str31 = 'a' * 31; // max fixstr
    final str32 = 'a' * 32; // min str 8

    final result31 = serialize(str31);
    expect(result31[0], 0xbf); // fixstr(31)

    final result32 = serialize(str32);
    expect(result32[0], 0xd9); // str 8
  });

  test('serializes fixarray to array 16 boundary correctly', () {
    final array15 = List.filled(15, 1); // max fixarray
    final array16 = List.filled(16, 1); // min array 16

    final result15 = serialize(array15);
    expect(result15[0], 0x9f); // fixarray(15)

    final result16 = serialize(array16);
    expect(result16[0], 0xdc); // array 16
  });

  test('serializes fixmap to map 16 boundary correctly', () {
    final map15 = Map.fromIterables(
      List.generate(15, (i) => i),
      List.generate(15, (i) => i),
    ); // max fixmap
    final map16 = Map.fromIterables(
      List.generate(16, (i) => i),
      List.generate(16, (i) => i),
    ); // min map 16

    final result15 = serialize(map15);
    expect(result15[0], 0x8f); // fixmap(15)

    final result16 = serialize(map16);
    expect(result16[0], 0xde); // map 16
  });

  group('Spec Compliance - Timestamp', () {
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

  group('serializeAll', () {
    test('serializes empty iterable', () {
      final result = serializeAll([]);
      expect(result, Uint8List.fromList([]));
    });

    test('serializes single value', () {
      final result = serializeAll([42]);
      // Should encode as positive fixint
      expect(result, Uint8List.fromList([0x2a /* 42 */]));
    });

    test('serializes multiple primitive values', () {
      final result = serializeAll([123, 'hello', true, null]);
      final expected = [
        0x7b, // 123 (positive fixint)
        0xa5, // fixstr with length 5
        0x68, 0x65, 0x6c, 0x6c, 0x6f, // 'hello'
        0xc3, // true
        0xc0, // nil
      ];
      expect(result, Uint8List.fromList(expected));
    });

    test('serializes mixed types sequentially', () {
      final result = serializeAll([
        42,
        'test',
        {'key': 'value'},
      ]);

      // Verify we can deserialize each value separately
      final deserializer = Deserializer(result);
      expect(deserializer.decode(), 42);
      expect(deserializer.decode(), 'test');
      expect(deserializer.decode(), {'key': 'value'});
      expect(deserializer.hasBytesAvailable, false);
    });

    test('differs from serialize() with array wrapping', () {
      final data = [1, 2, 3];

      // serializeAll: three consecutive integers
      final resultAll = serializeAll(data);
      expect(resultAll, Uint8List.fromList([0x01, 0x02, 0x03]));

      // serialize: one array with three elements
      final resultArray = serialize(data);
      expect(
        resultArray,
        Uint8List.fromList([0x93 /* fixarray len=3 */, 0x01, 0x02, 0x03]),
      );
    });

    test('works with List<Object?>', () {
      final values = <Object?>[1, 'test', null];
      final result = serializeAll(values);
      expect(result.isNotEmpty, true);
    });

    test('works with non-List iterable', () {
      final values = {1, 2, 3}.map((x) => x * 2); // Iterable but not List
      final result = serializeAll(values);
      // Should contain: 2, 4, 6 as positive fixints
      expect(result, Uint8List.fromList([0x02, 0x04, 0x06]));
    });

    test('supports custom extension encoder', () {
      final date = DateTime.utc(2020);
      final result = serializeAll([date]);
      // Should encode as timestamp extension
      expect(result[0], 0xd6); // fixext4 or another ext format
    });

    test('respects initialBufferSize', () {
      // Should not throw with small or large buffer sizes
      serializeAll([1, 2, 3], initialBufferSize: 16);
      serializeAll([1, 2, 3], initialBufferSize: 8192);
      // Test passes if no exception is thrown
    });

    test('encodes complex nested structures', () {
      final result = serializeAll([
        {
          'users': [1, 2, 3],
        },
        [true, false],
        'end',
      ]);

      // Verify deserialization
      final deserializer = Deserializer(result);
      expect(deserializer.decode(), {
        'users': [1, 2, 3],
      });
      expect(deserializer.decode(), [true, false]);
      expect(deserializer.decode(), 'end');
    });
  });

  test('Float toString', () {
    expect(Float(1.2).toString(), 'Float(1.2)');
  });

  test('serializes ByteData correctly', () {
    final bd = ByteData(2)..setUint16(0, 0x1234);
    final result = serialize(bd);
    expect(result, Uint8List.fromList([0xc4, 0x02, 0x12, 0x34]));
  });

  group('Serializer Edge Cases', () {
    test('Iterable is not List', () {
      final s = Serializer()..encode({1, 2, 3}); // Set is Iterable but not List
      final bytes = s.takeBytes();
      final d = Deserializer(bytes);
      expect(d.decode(), [1, 2, 3]);
    });

    test('writeExt with resolvedType but no extEncoder', () {
      final s = Serializer(); // No extEncoder
      expect(
        () => s.writeExt(Object(), 10),
        throwsA(
          isA<MessagePackConfigurationException>().having(
            (e) => e.message,
            'message',
            contains('Unable to encode object'),
          ),
        ),
      );
    });

    test('writeExt invalid type range', () {
      final s = Serializer(extEncoder: _MockInvalidTypeEncoder());
      expect(
        () => s.encode(Object()),
        throwsA(
          isA<MessagePackConfigurationException>().having(
            (e) => e.message,
            'message',
            contains('Type must be in the range'),
          ),
        ),
      );
    });

    test('writeExt success path in encode', () {
      final s = Serializer(extEncoder: _MockSuccessEncoder())..encode(Object());
      final bytes = s.takeBytes();
      expect(bytes, [0xd4, 0x0a, 0x00]);
    });
  });
}

class _MockInvalidTypeEncoder implements ExtEncoder {
  @override
  int? extTypeForObject(Object? object) => 200;
  @override
  Uint8List encodeObject(Object? object) => Uint8List(0);
}

class _MockSuccessEncoder implements ExtEncoder {
  @override
  int? extTypeForObject(Object? object) => 10;
  @override
  Uint8List encodeObject(Object? object) => Uint8List.fromList([0]);
}

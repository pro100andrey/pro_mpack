import 'dart:typed_data';

import 'package:pro_mpack/pro_mpack.dart';
import 'package:test/test.dart';

import '../utils/types.dart';

void main() {
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
        0x00,
        0x01,
        0x11,
        0x70, // Длина строки 70000 в формате big-endian
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
    final extEncoder = createCustomEncoder();
    final result = serialize(
      CustomExtension(1, Uint8List.fromList([42])),
      encodeExt: extEncoder,
    );
    expect(result, Uint8List.fromList([0xd4 /* fixext 1 */, 1, 42]));
  });

  test('serializes fixext 2 format correctly', () {
    final extEncoder = createCustomEncoder();
    final result = serialize(
      CustomExtension(2, Uint8List.fromList([42, 43])),
      encodeExt: extEncoder,
    );
    expect(result, Uint8List.fromList([0xd5 /* fixext 2 */, 2, 42, 43]));
  });

  test('serializes fixext 4 format correctly', () {
    final extEncoder = createCustomEncoder();
    final result = serialize(
      CustomExtension(3, Uint8List.fromList([42, 43, 44, 45])),
      encodeExt: extEncoder,
    );
    expect(
      result,
      Uint8List.fromList([0xd6 /* fixext 4 */, 3, 42, 43, 44, 45]),
    );
  });

  test('serializes fixext 8 format correctly', () {
    final extEncoder = createCustomEncoder();
    final result = serialize(
      CustomExtension(
        4,
        Uint8List.fromList([42, 43, 44, 45, 46, 47, 48, 49]),
      ),
      encodeExt: extEncoder,
    );
    expect(
      result,
      Uint8List.fromList(
        [0xd7 /* fixext 8 */, 4, 42, 43, 44, 45, 46, 47, 48, 49],
      ),
    );
  });

  test('serializes fixext 16 format correctly', () {
    final extEncoder = createCustomEncoder();
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
      encodeExt: extEncoder,
    );
    expect(
      result,
      Uint8List.fromList([
        0xd8 /* fixext 16 */,
        5, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, //
      ]),
    );
  });

  // Timestamp tests
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
      final extEncoder = createCustomEncoder();
      expect(
        () => serialize(RegExp(''), encodeExt: extEncoder),
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
    final extEncoder = createCustomEncoder();
    final data = Uint8List.fromList(List.filled(32, 42));
    final result = serialize(
      CustomExtension(10, data),
      encodeExt: extEncoder,
    );
    expect(
      result.sublist(0, 3),
      Uint8List.fromList([0xc7 /* ext 8 */, 32, 10]),
    );
  });

  test('serializes ext 16 format correctly', () {
    final extEncoder = createCustomEncoder();
    final data = Uint8List.fromList(List.filled(256, 42));
    final result = serialize(
      CustomExtension(11, data),
      encodeExt: extEncoder,
    );
    expect(
      result.sublist(0, 4),
      Uint8List.fromList([0xc8 /* ext 16 */, 0x01, 0x00, 11]),
    );
  });

  test('serializes ext 32 format correctly', () {
    final extEncoder = createCustomEncoder();
    final data = Uint8List.fromList(List.filled(70000, 42));
    final result = serialize(
      CustomExtension(12, data),
      encodeExt: extEncoder,
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

  test('serializes ByteData correctly', () {
    final bd = ByteData(2)..setUint16(0, 0x1234);
    final result = serialize(bd);
    expect(result, Uint8List.fromList([0xc4, 0x02, 0x12, 0x34]));
  });
}

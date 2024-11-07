import 'dart:typed_data';

import 'package:pro_mpack/pro_mpack.dart';
import 'package:test/test.dart';

import 'utils/utils.dart';

void main() {
  // Type system tests

  // Nil format
  test('Serialize nil', () {
    final result = serialize(null);
    expect(result, Uint8List.fromList([0xc0 /* nil */]));
  });

  // Boolean formats
  test('Serialize false', () {
    final result = serialize(false);
    expect(result, Uint8List.fromList([0xc2 /* false */]));
  });

  test('Serialize true', () {
    final result = serialize(true);
    expect(result, Uint8List.fromList([0xc3 /* true */]));
  });

  // Integer formats
  test('Serialize positive fixint', () {
    final result = serialize(127);
    expect(result, Uint8List.fromList([0x7f /* 127 */]));
  });

  test('Serialize negative fixint', () {
    final result = serialize(-32);
    expect(result, Uint8List.fromList([0xe0 /* -32 */]));
  });

  test('Serialize uint 8', () {
    final result = serialize(128);
    expect(result, Uint8List.fromList([0xcc /* uint 8 */, 0x80])); // 128
  });

  test('Serialize uint 16', () {
    final result = serialize(256);
    expect(result, Uint8List.fromList([0xcd /* uint 16 */, 0x01, 0x00])); // 256
  });

  test('Serialize uint 32', () {
    final result = serialize(65536);
    expect(
      result,
      Uint8List.fromList(
        [0xce /* uint 32 */, 0x00, 0x01, 0x00, 0x00],
      ),
    ); // 65536
  });

  test('Serialize uint 64', () {
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

  test('Serialize int 8', () {
    final result = serialize(-48);
    expect(result, Uint8List.fromList([0xd0 /* int 8 */, 0xd0])); // -48
  });

  test('Serialize int 16', () {
    final result = serialize(-32768);
    expect(
      result,
      Uint8List.fromList([0xd1 /* int 16 */, 0x80, 0x00]),
    ); // -32768
  });

  test('Serialize int 32', () {
    final result = serialize(-2147483648);
    expect(
      result,
      Uint8List.fromList([0xd2 /* int 32 */, 0x80, 0x00, 0x00, 0x00]),
    ); // -2147483648
  });

  test('Serialize int 64', () {
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
  test('Serialize float 32', () {
    final result = serialize(Float(3.1415927));
    expect(
      result,
      Uint8List.fromList(
        [0xca /* float 32 */, 0x40, 0x49, 0x0f, 0xdb],
      ),
    ); // 3.1415927
  });

  test('Serialize float 64', () {
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
  test('Serialize fixstr', () {
    final result = serialize('hello');
    expect(
      result,
      Uint8List.fromList(
        [0xa5 /* fixstr (5) */, 0x68, 0x65, 0x6c, 0x6c, 0x6f],
      ),
    ); // "hello"
  });

  test('Serialize str 8', () {
    final longString = 'a' * 32; // Длина строки 32 символа
    final result = serialize(longString);
    expect(
      result,
      Uint8List.fromList(
        [0xd9 /* str 8 */, 32, ...List.filled(32, 0x61)],
      ),
    ); // "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  });

  test('Serialize str 16', () {
    final longString = 'a' * 256; // Длина строки 256 символов
    final result = serialize(longString);
    expect(
      result,
      Uint8List.fromList(
        [0xda /* str 16 */, 0x01, 0x00, ...List.filled(256, 0x61)],
      ),
    ); // 256 'a's
  });

  test('Serialize str 32', () {
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
  test('Serialize bin 8', () {
    final result = serialize(Uint8List.fromList([1, 2, 3]));
    expect(
      result,
      Uint8List.fromList([0xc4 /* bin 8 */, 3, 1, 2, 3]),
    ); // [1, 2, 3]
  });

  test('Serialize bin 16', () {
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

  test('Serialize bin 32', () {
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
  test('Serialize fixarray', () {
    final result = serialize([1, 2, 3]);
    expect(
      result,
      Uint8List.fromList([0x93 /* fixarray (3) */, 1, 2, 3]),
    ); // [1, 2, 3]
  });

  test('Serialize array 16', () {
    final result = serialize(List.filled(256, 0x01));
    expect(
      result,
      Uint8List.fromList(
        [0xdc /* array 16 */, 0x01, 0x00, ...List.filled(256, 0x01)],
      ),
    ); // [1, 1, 1, ..., 1] (256 times)
  });

  test('Serialize array 32', () {
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
  test('Serialize fixmap', () {
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

  test('Serialize map 16', () {
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

  test('Serialize map 32', () {
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
  test('Serialize fixext 1', () {
    final extEncoder = TestExtEncoder();
    final result = serialize(
      CustomExtension(1, Uint8List.fromList([42])),
      extEncoder: extEncoder,
    );
    expect(result, Uint8List.fromList([0xd4 /* fixext 1 */, 1, 42]));
  });

  test('Serialize fixext 2', () {
    final extEncoder = TestExtEncoder();
    final result = serialize(
      CustomExtension(2, Uint8List.fromList([42, 43])),
      extEncoder: extEncoder,
    );
    expect(result, Uint8List.fromList([0xd5 /* fixext 2 */, 2, 42, 43]));
  });

  test('Serialize fixext 4', () {
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

  test('Serialize fixext 8', () {
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

  test('Serialize fixext 16', () {
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
  test('Serialize timestamp 32', () {
    final timestamp = DateTime.utc(1970, 1, 1, 0, 0, 1);
    final result = serialize(
      timestamp,
      extEncoder: CustomTypesExtEncoder(
        timeStampFormat: TimeStampFormat.ts32,
      ),
    );
    expect(
      result,
      Uint8List.fromList([0xd6 /* fixext 4 */, -1, 0x00, 0x00, 0x00, 0x01]),
    );
  });

  test('Serialize timestamp 64', () {
    final timestamp = DateTime.utc(1970, 1, 1, 0, 0, 1, 0, 2);
    final result = serialize(
      timestamp,
      extEncoder: CustomTypesExtEncoder(
        timeStampFormat: TimeStampFormat.ts64,
      ),
    );
    expect(
      result,
      Uint8List.fromList([
        0xd7 /* fixext 8 */,
        -1,
        0x00,
        0x00,
        0x07,
        0xd0,
        0x00,
        0x00,
        0x00,
        0x01,
      ]),
    );
  });

  test('Serialize unsupported object throws exception', () {
    expect(() => serialize(Object()), throwsException);
  });

  test('Serialize int beyond fixint range', () {
    final result = serialize(-33);
    expect(result, Uint8List.fromList([0xd0, 0xdf]));
  });

  test('Serialize large uint 64', () {
    final result = serialize(9223372036854775807);
    expect(
      result,
      Uint8List.fromList(
        [0xcf, 0x7f, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff],
      ),
    );
  });

  test('Serialize unsupported ext type', () {
    final extEncoder = TestExtEncoder();
    expect(
      () => serialize(DateTime.now(), extEncoder: extEncoder),
      throwsException,
    );
  });

  test('Serialize array with complex objects', () {
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

  test('Serialize map with non-string keys', () {
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

  test('Serialize empty map', () {
    final result = serialize({});
    expect(result, Uint8List.fromList([0x80]));
  });
}

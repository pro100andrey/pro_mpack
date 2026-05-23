import 'dart:typed_data';

import 'package:pro_mpack/pro_mpack.dart';
import 'package:test/test.dart';

import 'utils/utils.dart';

void main() {
  // Nil format
  test('deserializes nil format correctly', () {
    final buffer = Uint8List.fromList([0xc0 /* nil */]);
    final result = deserialize(buffer);
    expect(result, isNull);
  });

  // Never used format (reserved)
  test('throws MessagePackFormatException on reserved byte 0xc1', () {
    final buffer = Uint8List.fromList([0xc1 /* never used */]);
    expect(
      () => deserialize(buffer),
      throwsA(
        isA<MessagePackFormatException>().having(
          (e) => e.message,
          'message',
          contains('reserved and never used'),
        ),
      ),
    );
  });

  test('throws MessagePackFormatException on 0xc1 in array', () {
    final buffer = Uint8List.fromList([
      0x92, // fixarray with 2 elements
      0x01, // first element: 1
      0xc1, // second element: never used byte
    ]);
    expect(
      () => deserialize(buffer),
      throwsA(
        isA<MessagePackFormatException>().having(
          (e) => e.message,
          'message',
          contains('reserved and never used'),
        ),
      ),
    );
  });

  test('throws MessagePackFormatException on 0xc1 as map value', () {
    final buffer = Uint8List.fromList([
      0x81, // fixmap with 1 key-value pair
      0xa3, ...'key'.codeUnits, // key: "key"
      0xc1, // value: never used byte
    ]);
    expect(
      () => deserialize(buffer),
      throwsA(
        isA<MessagePackFormatException>().having(
          (e) => e.message,
          'message',
          contains('reserved and never used'),
        ),
      ),
    );
  });

  // Boolean formats
  test('deserializes false format correctly', () {
    final buffer = Uint8List.fromList([0xc2 /* false */]);
    final result = deserialize(buffer);
    expect(result, isFalse);
  });

  test('deserializes true format correctly', () {
    final buffer = Uint8List.fromList([0xc3 /* true */]);
    final result = deserialize(buffer);
    expect(result, isTrue);
  });

  // Integer formats
  test('deserializes zero as positive fixint', () {
    final buffer = Uint8List.fromList([0x00]);
    final result = deserialize(buffer);
    expect(result, 0);
  });

  test('deserializes positive fixint correctly', () {
    final buffer = Uint8List.fromList([0x7f /*127*/]);
    final result = deserialize(buffer);
    expect(result, 127);
  });

  test('deserializes negative fixint correctly', () {
    final buffer = Uint8List.fromList([0xe0 /*-32*/]);
    final result = deserialize(buffer);
    expect(result, -32);
  });

  test('deserializes minimum negative fixint', () {
    final buffer = Uint8List.fromList([0xff /*-1*/]);
    final result = deserialize(buffer);
    expect(result, -1);
  });

  test('deserializes uint 8 format correctly', () {
    final buffer = Uint8List.fromList([0xcc /*uint 8*/, 0x80]); // 128
    final result = deserialize(buffer);
    expect(result, 128);
  });

  test('deserializes uint 16 format correctly', () {
    final buffer = Uint8List.fromList([0xcd /*uint 16*/, 0x01, 0x00]); // 256
    final result = deserialize(buffer);
    expect(result, 256);
  });

  test('deserializes uint 32 format correctly', () {
    final buffer = Uint8List.fromList(
      [0xce /*uint 32*/, 0x00, 0x01, 0x00, 0x00],
    ); // 65536
    final result = deserialize(buffer);
    expect(result, 65536);
  });

  test('deserializes uint 64 format correctly', () {
    final buffer = Uint8List.fromList(
      [0xcf /*uint 64*/, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00],
    ); // 4294967296
    final result = deserialize(buffer);
    expect(result, 4294967296);
  });

  test('deserializes int 8 format correctly', () {
    final buffer = Uint8List.fromList([0xd0 /*int 8*/, 0xd0]); // -48
    final result = deserialize(buffer);
    expect(result, -48);
  });

  test('deserializes int 16 format correctly', () {
    final buffer = Uint8List.fromList([0xd1 /*int 16*/, 0xff, 0xff]); // -1
    final result = deserialize(buffer);
    expect(result, -1);
  });

  test('deserializes int 32 format correctly', () {
    final buffer = Uint8List.fromList(
      [0xd2 /*int 32*/, 0xFF, 0xFF, 0xFF, 0xFF],
    ); // -1
    final result = deserialize(buffer);
    expect(result, -1);
  });

  test('deserializes int 64 format correctly', () {
    final buffer = Uint8List.fromList(
      [0xd3 /*int 64*/, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff],
    ); // -1
    final result = deserialize(buffer);
    expect(result, -1);
  });

  test('deserializes maximum int 64 value correctly', () {
    final buffer = Uint8List.fromList(
      [0xd3 /*int 64*/, 0x7f, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff],
    ); // 9223372036854775807
    final result = deserialize(buffer);
    expect(result, 9223372036854775807);
  });

  test('deserializes minimum int 64 value correctly', () {
    final buffer = Uint8List.fromList(
      [0xd3 /*int 64*/, 0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00],
    ); // -9223372036854775808
    final result = deserialize(buffer);
    expect(result, -9223372036854775808);
  });

  // Float formats
  test('deserializes float 32 format correctly', () {
    final buffer = Uint8List.fromList(
      [0xca /*float 32*/, 0x40, 0x49, 0x0f, 0xdb],
    ); // 3.1415927

    final result = deserialize(buffer);
    expect((result! as double).toStringAsPrecision(7), '3.141593');
  });

  test('deserializes float 64 format correctly', () {
    final buffer = Uint8List.fromList([
      0xcb /*float 64*/,
      0x40,
      0x09,
      0x21,
      0xFB,
      0x54,
      0x44,
      0x2D,
      0x18,
    ]); // 3.141592653589793
    final result = deserialize(buffer);
    expect(result, 3.141592653589793);
  });

  // String formats
  test('deserializes fixstr format correctly', () {
    final buffer = Uint8List.fromList(
      [0xa5 /*0xa0 - 0xbf*/, ...'hello'.codeUnits],
    );

    final result = deserialize(buffer);
    expect(result, 'hello');
  });

  test('deserializes str 8 format correctly', () {
    final buffer = Uint8List.fromList(
      [0xd9 /*str 8*/, 5, ...'world'.codeUnits],
    );
    final result = deserialize(buffer);
    expect(result, 'world');
  });

  test('deserializes str 16 format correctly', () {
    final buffer = Uint8List.fromList(
      [0xda /*str 16*/, 0x00, 0x04, ...'Dart'.codeUnits], // "Dart"
    );
    final result = deserialize(buffer);
    expect(result, 'Dart');
  });

  test('deserializes str 32 format correctly', () {
    final longString = 'a' * 70000;
    final buffer = Uint8List.fromList(
      [0xdb /*str 32*/, 0x00, 0x01, 0x11, 0x70, ...longString.codeUnits],
    ); // 70000 'a's
    final result = deserialize(buffer);
    expect(result, longString);
  });

  // Binary formats
  test('deserializes bin 8 format correctly', () {
    final buffer = Uint8List.fromList([0xc4 /*bin 8*/, 3, 1, 2, 3]);
    final result = deserialize(buffer);
    expect(result, Uint8List.fromList([1, 2, 3]));
  });

  test('deserializes bin 16 format correctly', () {
    final buffer = Uint8List.fromList([0xc5 /*bin 16*/, 0x00, 0x03, 1, 2, 3]);
    final result = deserialize(buffer);
    expect(result, Uint8List.fromList([1, 2, 3]));
  });

  test('deserializes bin 32 format correctly', () {
    final buffer = Uint8List.fromList(
      [0xc6 /*bin 32*/, 0x00, 0x00, 0x00, 0x03, 1, 2, 3],
    );
    final result = deserialize(buffer);
    expect(result, Uint8List.fromList([1, 2, 3]));
  });

  // Array formats
  test('deserializes fixarray format correctly', () {
    final buffer = Uint8List.fromList(
      [0x93 /*fixarray*/, 1, 2, 3],
    ); // [1, 2, 3]
    final result = deserialize(buffer);
    expect(result, [1, 2, 3]);
  });

  test('deserializes array 16 format correctly', () {
    final buffer = Uint8List.fromList(
      [0xdc /*array 16*/, 0x00, 0x04, 1, 2, 3, 4],
    ); // [1, 2, 3]
    final result = deserialize(buffer);
    expect(result, [1, 2, 3, 4]);
  });

  test('deserializes array 32 format correctly', () {
    final buffer = Uint8List.fromList(
      [0xdd /*array 32*/, 0x00, 0x00, 0x00, 0x03, 1, 2, 3],
    ); // [1, 2, 3]
    final result = deserialize(buffer);
    expect(result, [1, 2, 3]);
  });

  // Map formats
  test('deserializes fixmap format correctly', () {
    final buffer = Uint8List.fromList([
      0x81 /*fixmap*/,
      0xa3,
      ...'key'.codeUnits,
      0xa5,
      ...'value'.codeUnits,
    ]); // {"key": "value"}
    final result = deserialize(buffer);
    expect(result, {'key': 'value'});
  });

  test('deserializes map 16 format correctly', () {
    final buffer = Uint8List.fromList([
      0xde /*map 16*/,
      0x00,
      0x01,
      0xa3,
      ...'key'.codeUnits,
      0xa5,
      ...'value'.codeUnits,
    ]); // {"key": "value"}
    final result = deserialize(buffer);
    expect(result, {'key': 'value'});
  });

  test('deserializes map 32 format correctly', () {
    final buffer = Uint8List.fromList([
      0xdf /*map 32*/,
      0x00,
      0x00,
      0x00,
      0x01,
      0xa3,
      ...'key'.codeUnits,
      0xa5,
      ...'value'.codeUnits,
    ]); // {"key": "value"}
    final result = deserialize(buffer);
    expect(result, {'key': 'value'});
  });

  // Extension formats
  test('deserializes fixext 1 format correctly', () {
    final buffer = Uint8List.fromList(
      [0xd4 /*fixext 1 */, 1, 42],
    ); // Custom extension
    final result = deserialize(
      buffer,
      extDecoder: CustomExtDecoder(),
    );
    expect(result, 'Custom ext type 1 with data [42]');
  });

  test('deserializes fixext 2 format correctly', () {
    final buffer = Uint8List.fromList(
      [0xd5 /*fixext 2 */, 2, 42, 43],
    ); // Custom extension
    final result = deserialize(
      buffer,
      extDecoder: CustomExtDecoder(),
    );
    expect(result, 'Custom ext type 2 with data [42, 43]');
  });

  test('deserializes fixext 4 format correctly', () {
    final buffer = Uint8List.fromList(
      [0xd6 /*fixext 4 */, 3, 42, 43, 44, 45],
    ); // Custom extension
    final result = deserialize(
      buffer,
      extDecoder: CustomExtDecoder(),
    );
    expect(result, 'Custom ext type 3 with data [42, 43, 44, 45]');
  });

  test('deserializes fixext 8 format correctly', () {
    final buffer = Uint8List.fromList(
      [0xd7 /*fixext 8 */, 4, 42, 43, 44, 45, 46, 47, 48, 49],
    ); // Custom extension
    final result = deserialize(
      buffer,
      extDecoder: CustomExtDecoder(),
    );
    expect(
      result,
      'Custom ext type 4 with data [42, 43, 44, 45, 46, 47, 48, 49]',
    );
  });

  test('deserializes fixext 16 format correctly', () {
    final buffer = Uint8List.fromList([
      0xd8 /*fixext 16 */,
      5, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, //
    ]); // Custom extension
    final result = deserialize(
      buffer,
      extDecoder: CustomExtDecoder(),
    );
    expect(
      result,
      'Custom ext type 5 with data '
      '[42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57]',
    );
  });

  // Timestamp extension type tests
  test('deserializes timestamp 32 format correctly', () {
    final buffer = Uint8List.fromList(
      [
        0xd6 /*fixext 4 */,
        0xff, 0x00, 0x00, 0x00, 0x01, //
      ], // 1970-01-01 00:00:01 UTC
    );
    final result = deserialize(buffer);
    expect(result, DateTime.utc(1970, 1, 1, 0, 0, 1));
  });

  test('deserializes timestamp 64 format correctly', () {
    final buffer = Uint8List.fromList([
      0xd7 /*fixext 8*/,
      0xff, 0x00, 0x00, 0x1f, 0x40, 0x00, 0x00, 0x00, 0x01, //
    ]); // 1970-01-01 00:00:01.000002 UTC

    final result = deserialize(buffer);
    expect(result, DateTime.utc(1970, 1, 1, 0, 0, 1, 0, 2));
  });

  test('deserializes timestamp 96 format correctly', () {
    final buffer = Uint8List.fromList([
      0xc7 /*fixext 8*/,
      12, 0xff, 0x00, 0x00, 0x07, 0xd0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, //
      0x00, 0x01,
    ]); // 1970-01-01 00:00:01.000002 UTC
    final result = deserialize(buffer);
    expect(result, DateTime.utc(1970, 1, 1, 0, 0, 1, 0, 2));
  });

  test('throws MessagePackFormatException on invalid timestamp length', () {
    final buffer = Uint8List.fromList([0xc7, 0x05, 0xff, 0, 0, 0, 0, 0]);
    expect(
      () => deserialize(buffer),
      throwsA(
        isA<MessagePackFormatException>().having(
          (e) => e.message,
          'message',
          contains('Invalid timestamp length'),
        ),
      ),
    );
  });
  // Extension format tests (ext 8, ext 16, ext 32)
  test('deserializes ext 8 format correctly', () {
    final buffer = Uint8List.fromList(
      [0xc7 /*ext 8*/, 3, 10, 1, 2, 3], // length 3, type 10, data [1,2,3]
    );
    final result = deserialize(
      buffer,
      extDecoder: CustomExtDecoder(),
    );
    expect(result, 'Custom ext type 10 with data [1, 2, 3]');
  });

  test('deserializes ext 16 format correctly', () {
    final data = List.filled(256, 42);
    final buffer = Uint8List.fromList(
      [0xc8 /*ext 16*/, 0x01, 0x00, 11, ...data], // length 256, type 11
    );
    final result = deserialize(
      buffer,
      extDecoder: CustomExtDecoder(),
    );
    expect(result, 'Custom ext type 11 with data $data');
  });

  test('deserializes ext 32 format correctly', () {
    final data = List.filled(300, 43);
    final buffer = Uint8List.fromList(
      [0xc9 /*ext 32*/, 0x00, 0x00, 0x01, 0x2c, 12, ...data],
    ); // length 300, type 12
    final result = deserialize(
      buffer,
      extDecoder: CustomExtDecoder(),
    );
    expect(result, 'Custom ext type 12 with data $data');
  });

  // Edge case tests
  test('deserializes empty array correctly', () {
    final buffer = Uint8List.fromList([0x90 /*fixarray(0)*/]);
    final result = deserialize(buffer);
    expect(result, isEmpty);
  });

  test('deserializes empty binary correctly', () {
    final buffer = Uint8List.fromList([0xc4 /*bin 8*/, 0]);
    final result = deserialize(buffer);
    expect(result, Uint8List(0));
  });

  test('deserializes empty string correctly', () {
    final buffer = Uint8List.fromList([0xa0 /*fixstr(0)*/]);
    final result = deserialize(buffer);
    expect(result, '');
  });

  test('deserializes empty map correctly', () {
    final buffer = Uint8List.fromList([0x80 /*fixmap(0)*/]);
    final result = deserialize(buffer);
    expect(result, isEmpty);
  });

  // Nested structure tests
  test('deserializes nested array correctly', () {
    final buffer = Uint8List.fromList(
      [0x92 /*fixarray(2)*/, 0x91 /*fixarray(1)*/, 1, 2],
    ); // [[1], 2]
    final result = deserialize(buffer);
    expect(result, <Object?>[
      [1],
      2,
    ]);
  });

  test('deserializes nested map correctly', () {
    final buffer = Uint8List.fromList([
      0x81 /*fixmap(1)*/,
      0xa1,
      0x61, // "a"
      0x81 /*fixmap(1)*/,
      0xa1,
      0x62, // "b"
      1,
    ]); // {"a": {"b": 1}}
    final result = deserialize(buffer);
    expect(result, <Object?, Object?>{
      'a': {'b': 1},
    });
  });

  group('preserveMapOrder', () {
    test('preserves map order when true', () {
      final buffer = Uint8List.fromList([
        0x83, // fixmap(3)
        0xa1, 0x7a, 1, // "z": 1
        0xa1, 0x61, 2, // "a": 2
        0xa1, 0x6d, 3, // "m": 3
      ]);
      final result = deserialize(buffer, preserveMapOrder: true)! as Map;
      expect(result.keys.toList(), ['z', 'a', 'm']);
    });

    test('does not guarantee map order when false (default)', () {
      final buffer = Uint8List.fromList([
        0x83, // fixmap(3)
        0xa1, 0x7a, 1, // "z": 1
        0xa1, 0x61, 2, // "a": 2
        0xa1, 0x6d, 3, // "m": 3
      ]);
      final result = deserialize(buffer, preserveMapOrder: false)! as Map;
      expect(result, isA<Map<dynamic, dynamic>>());
      expect(result, {
        'z': 1,
        'a': 2,
        'm': 3,
      });
    });
  });

  group('deserializeAll', () {
    test('deserializes empty buffer', () {
      final buffer = Uint8List.fromList([]);
      final result = deserializeAll(buffer);
      expect(result, isEmpty);
    });

    test('deserializes single value', () {
      final buffer = Uint8List.fromList([0x2a /* 42 */]);
      final result = deserializeAll(buffer);
      expect(result, [42]);
    });

    test('deserializes multiple primitive values', () {
      final buffer = Uint8List.fromList([
        0x7b, // 123
        0xa5, // fixstr with length 5
        0x68, 0x65, 0x6c, 0x6c, 0x6f, // 'hello'
        0xc3, // true
        0xc0, // nil
      ]);
      final result = deserializeAll(buffer);
      expect(result, [123, 'hello', true, null]);
    });

    test('deserializes mixed types sequentially', () {
      // Encode multiple values
      final bytes = serializeAll([
        42,
        'test',
        {'key': 'value'},
      ]);

      // Deserialize all at once
      final result = deserializeAll(bytes);
      expect(result.length, 3);
      expect(result[0], 42);
      expect(result[1], 'test');
      expect(result[2], {'key': 'value'});
    });

    test('differs from deserialize() with arrays', () {
      // Three separate integers (no array wrapper)
      final bufferAll = Uint8List.fromList([0x01, 0x02, 0x03]);
      final resultAll = deserializeAll(bufferAll);
      expect(resultAll, [1, 2, 3]);
      expect(resultAll, isA<List<Object?>>());

      // One array with three elements
      final bufferArray = Uint8List.fromList([
        0x93, // fixarray len=3
        0x01,
        0x02,
        0x03,
      ]);
      final resultArray = deserialize(bufferArray);
      expect(resultArray, [1, 2, 3]);

      // Both have same values but different representations
      expect(resultAll, equals(resultArray));
    });

    test('round-trip with serializeAll', () {
      final original = [
        123,
        'hello',
        true,
        null,
        [1, 2],
        {'a': 'b'},
      ];
      final bytes = serializeAll(original);
      final result = deserializeAll(bytes);
      expect(result, original);
    });

    test('decodes built-in timestamp extension', () {
      final date = DateTime.utc(2020);
      final bytes = serializeAll([date]);
      final result = deserializeAll(bytes);

      expect(result.length, 1);
      expect(result[0], isA<DateTime>());
      expect((result[0]! as DateTime).year, 2020);
    });

    test('handles complex nested structures', () {
      final original = [
        {
          'users': [1, 2, 3],
        },
        [true, false],
        'end',
      ];

      final bytes = serializeAll(original);
      final result = deserializeAll(bytes);

      expect(result.length, 3);
      expect(result[0], {
        'users': [1, 2, 3],
      });
      expect(result[1], [true, false]);
      expect(result[2], 'end');
    });

    test('processes all available bytes', () {
      // Create buffer with 5 integers
      final buffer = Uint8List.fromList([0x01, 0x02, 0x03, 0x04, 0x05]);
      final result = deserializeAll(buffer);
      expect(result, [1, 2, 3, 4, 5]);
    });

    test('handles strings correctly', () {
      final buffer = Uint8List.fromList([
        0xa3, // fixstr len=3
        0x66, 0x6f, 0x6f, // 'foo'
        0xa3, // fixstr len=3
        0x62, 0x61, 0x72, // 'bar'
      ]);
      final result = deserializeAll(buffer);
      expect(result, ['foo', 'bar']);
    });

    test('throws on incomplete data', () {
      // str8 format says there are 10 bytes but buffer ends early
      final buffer = Uint8List.fromList([
        0xd9, // str8 format
        0x0a, // length = 10
        0x68, 0x69, // only 2 bytes provided (incomplete)
      ]);
      expect(
        () => deserializeAll(buffer),
        throwsA(isA<RangeError>()),
      );
    });

    test('stops at exact buffer end', () {
      // Three values that exactly fill the buffer
      final buffer = Uint8List.fromList([
        0xc3, // true
        0xc2, // false
        0xc0, // nil
      ]);
      final result = deserializeAll(buffer);
      expect(result, [true, false, null]);
      expect(result.length, 3);
    });
  });
}

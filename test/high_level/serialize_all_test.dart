import 'dart:typed_data';

import 'package:pro_mpack/pro_mpack.dart';
import 'package:test/test.dart';

void main() {
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
      final deserializer = Unpacker(buffer: result);
      expect(deserializer.unpack(), 42);
      expect(deserializer.unpack(), 'test');
      expect(deserializer.unpack(), {'key': 'value'});
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
      final deserializer = Unpacker(buffer: result);
      expect(deserializer.unpack(), {
        'users': [1, 2, 3],
      });
      expect(deserializer.unpack(), [true, false]);
      expect(deserializer.unpack(), 'end');
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

import 'dart:typed_data';

import 'package:pro_mpack/pro_mpack.dart';
import 'package:test/test.dart';

import 'utils/utils.dart';

void main() {
  // Type system tests

  // Nil format
  test('Deserialize nil', () {
    final buffer = Uint8List.fromList([0xc0 /* nil */]);
    final result = deserialize(buffer);
    expect(result, isNull);
  });

  // Boolean formats
  test('Deserialize false', () {
    final buffer = Uint8List.fromList([0xc2 /* false */]);
    final result = deserialize(buffer);
    expect(result, isFalse);
  });

  test('Deserialize true', () {
    final buffer = Uint8List.fromList([0xc3 /* true */]);
    final result = deserialize(buffer);
    expect(result, isTrue);
  });

  // Integer formats
  test('Deserialize positive fixint', () {
    final buffer = Uint8List.fromList([0x7f /*127*/]);
    final result = deserialize(buffer);
    expect(result, 127);
  });

  test('Deserialize negative fixint', () {
    final buffer = Uint8List.fromList([0xe0 /*-32*/]);
    final result = deserialize(buffer);
    expect(result, -32);
  });

  test('Deserialize uint 8', () {
    final buffer = Uint8List.fromList([0xcc /*uint 8*/, 0x80]); // 128
    final result = deserialize(buffer);
    expect(result, 128);
  });

  test('Deserialize uint 16', () {
    final buffer = Uint8List.fromList([0xcd /*uint 16*/, 0x01, 0x00]); // 256
    final result = deserialize(buffer);
    expect(result, 256);
  });

  test('Deserialize uint 32', () {
    final buffer = Uint8List.fromList(
      [0xce /*uint 32*/, 0x00, 0x01, 0x00, 0x00],
    ); // 65536
    final result = deserialize(buffer);
    expect(result, 65536);
  });

  test('Deserialize uint 64', () {
    final buffer = Uint8List.fromList(
      [0xcf /*uint 64*/, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00],
    ); // 4294967296
    final result = deserialize(buffer);
    expect(result, 4294967296);
  });

  test('Deserialize int 8', () {
    final buffer = Uint8List.fromList([0xd0 /*int 8*/, 0xd0]); // -48
    final result = deserialize(buffer);
    expect(result, -48);
  });

  test('Deserialize int 16', () {
    final buffer = Uint8List.fromList([0xd1 /*int 16*/, 0xff, 0xff]); // -1
    final result = deserialize(buffer);
    expect(result, -1);
  });

  test('Deserialize int 32', () {
    final buffer = Uint8List.fromList(
      [0xd2 /*int 32*/, 0xFF, 0xFF, 0xFF, 0xFF],
    ); // -1
    final result = deserialize(buffer);
    expect(result, -1);
  });

  test('Deserialize int 64', () {
    final buffer = Uint8List.fromList(
      [0xd3 /*int 64*/, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff],
    ); // -1
    final result = deserialize(buffer);
    expect(result, -1);
  });

  // Float formats
  test('Deserialize float 32', () {
    final buffer = Uint8List.fromList(
      [0xca /*float 32*/, 0x40, 0x49, 0x0f, 0xdb],
    ); // 3.1415927

    final result = deserialize(buffer);
    expect((result! as double).toStringAsPrecision(7), '3.141593');
  });

  test('Deserialize float 64', () {
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
  test('Deserialize fixstr', () {
    final buffer = Uint8List.fromList(
      [0xa5 /*0xa0 - 0xbf*/, ...'hello'.codeUnits],
    );

    final result = deserialize(buffer);
    expect(result, 'hello');
  });

  test('Deserialize str 8', () {
    final buffer = Uint8List.fromList(
      [0xd9 /*str 8*/, 5, ...'world'.codeUnits],
    );
    final result = deserialize(buffer);
    expect(result, 'world');
  });

  test('Deserialize str 16', () {
    final buffer = Uint8List.fromList(
      [0xda /*str 16*/, 0x00, 0x04, ...'Dart'.codeUnits], // "Dart"
    );
    final result = deserialize(buffer);
    expect(result, 'Dart');
  });

  test('Deserialize str 32', () {
    final longString = 'a' * 70000;
    final buffer = Uint8List.fromList(
      [0xdb /*str 32*/, 0x00, 0x01, 0x11, 0x70, ...longString.codeUnits],
    ); // 70000 'a's
    final result = deserialize(buffer);
    expect(result, longString);
  });

  // Binary formats
  test('Deserialize bin 8', () {
    final buffer = Uint8List.fromList([0xc4 /*bin 8*/, 3, 1, 2, 3]);
    final result = deserialize(buffer);
    expect(result, Uint8List.fromList([1, 2, 3]));
  });

  test('Deserialize bin 16', () {
    final buffer = Uint8List.fromList([0xc5 /*bin 16*/, 0x00, 0x03, 1, 2, 3]);
    final result = deserialize(buffer);
    expect(result, Uint8List.fromList([1, 2, 3]));
  });

  test('Deserialize bin 32', () {
    final buffer = Uint8List.fromList(
      [0xc6 /*bin 32*/, 0x00, 0x00, 0x00, 0x03, 1, 2, 3],
    );
    final result = deserialize(buffer);
    expect(result, Uint8List.fromList([1, 2, 3]));
  });

  // Array formats
  test('Deserialize fixarray', () {
    final buffer = Uint8List.fromList(
      [0x93 /*fixarray*/, 1, 2, 3],
    ); // [1, 2, 3]
    final result = deserialize(buffer);
    expect(result, [1, 2, 3]);
  });

  test('Deserialize array 16', () {
    final buffer = Uint8List.fromList(
      [0xdc /*array 16*/, 0x00, 0x04, 1, 2, 3, 4],
    ); // [1, 2, 3]
    final result = deserialize(buffer);
    expect(result, [1, 2, 3, 4]);
  });

  test('Deserialize array 32', () {
    final buffer = Uint8List.fromList(
      [0xdd /*array 32*/, 0x00, 0x00, 0x00, 0x03, 1, 2, 3],
    ); // [1, 2, 3]
    final result = deserialize(buffer);
    expect(result, [1, 2, 3]);
  });

  // Map formats
  test('Deserialize fixmap', () {
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

  test('Deserialize map 16', () {
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

  test('Deserialize map 32', () {
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
  test('Deserialize fixext 1', () {
    final buffer = Uint8List.fromList(
      [0xd4 /*fixext 1 */, 1, 42],
    ); // Custom extension
    final result = deserialize(
      buffer,
      extDecoder: CustomExtDecoder(),
    );
    expect(result, 'Custom ext type 1 with data [42]');
  });

  test('Deserialize fixext 2', () {
    final buffer = Uint8List.fromList(
      [0xd5 /*fixext 2 */, 2, 42, 43],
    ); // Custom extension
    final result = deserialize(
      buffer,
      extDecoder: CustomExtDecoder(),
    );
    expect(result, 'Custom ext type 2 with data [42, 43]');
  });

  test('Deserialize fixext 4', () {
    final buffer = Uint8List.fromList(
      [0xd6 /*fixext 4 */, 3, 42, 43, 44, 45],
    ); // Custom extension
    final result = deserialize(
      buffer,
      extDecoder: CustomExtDecoder(),
    );
    expect(result, 'Custom ext type 3 with data [42, 43, 44, 45]');
  });

  test('Deserialize fixext 8', () {
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

  test('Deserialize fixext 16', () {
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
  test('Deserialize timestamp 32', () {
    final buffer = Uint8List.fromList(
      [
        0xd6 /*fixext 4 */,
        0xff, 0x00, 0x00, 0x00, 0x01, //
      ], // 1970-01-01 00:00:01 UTC
    );
    final result = deserialize(
      buffer,
      extDecoder: CustomTypesExtDecoder(),
    );
    expect(result, DateTime.utc(1970, 1, 1, 0, 0, 1));
  });

  test('Deserialize timestamp 64', () {
    final buffer = Uint8List.fromList([
      0xd7 /*fixext 8*/,
      0xff, 0x00, 0x00, 0x07, 0xd0, 0x00, 0x00, 0x00, 0x01, //
    ]); // 1970-01-01 00:00:01.000002 UTC

    final result = deserialize(
      buffer,
      extDecoder: CustomTypesExtDecoder(),
    );
    expect(result, DateTime.utc(1970, 1, 1, 0, 0, 1, 0, 2));
  });

  test('Deserialize timestamp 96', () {
    final buffer = Uint8List.fromList([
      0xc7 /*fixext 8*/,
      12, 0xff, 0x00, 0x00, 0x07, 0xd0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, //
      0x00, 0x01,
    ]); // 1970-01-01 00:00:01.000002 UTC
    final result = deserialize(
      buffer,
      extDecoder: CustomTypesExtDecoder(),
    );
    expect(result, DateTime.utc(1970, 1, 1, 0, 0, 1, 0, 2));
  });
}

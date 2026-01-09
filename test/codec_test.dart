import 'dart:convert';
import 'dart:typed_data';

import 'package:pro_mpack/pro_mpack.dart';
import 'package:test/test.dart';

import 'utils/utils.dart';

void main() {
  group('MessagePackCodec', () {
    test('creates codec with default parameters', () {
      const codec = MessagePackCodec();
      expect(codec.registry, isNull);
      expect(codec.defaultBufferSize, 1024);
    });

    test('creates codec with custom registry', () {
      final registry = MessagePackRegistry();
      final codec = MessagePackCodec(registry: registry);
      expect(codec.registry, registry);
    });

    test('creates codec with custom buffer size', () {
      const codec = MessagePackCodec(defaultBufferSize: 2048);
      expect(codec.defaultBufferSize, 2048);
    });

    test('provides encoder', () {
      const codec = MessagePackCodec();
      expect(codec.encoder, isA<Converter<Object?, Uint8List>>());
    });

    test('provides decoder', () {
      const codec = MessagePackCodec();
      expect(codec.decoder, isA<Converter<Uint8List, Object?>>());
    });
  });

  group('MessagePackCodec encoding', () {
    const codec = MessagePackCodec();

    test('encodes null', () {
      final result = codec.encode(null);
      expect(result, Uint8List.fromList([0xc0]));
    });

    test('encodes bool true', () {
      final result = codec.encode(true);
      expect(result, Uint8List.fromList([0xc3]));
    });

    test('encodes bool false', () {
      final result = codec.encode(false);
      expect(result, Uint8List.fromList([0xc2]));
    });

    test('encodes positive integer', () {
      final result = codec.encode(42);
      expect(result, Uint8List.fromList([0x2a]));
    });

    test('encodes negative integer', () {
      final result = codec.encode(-1);
      expect(result, Uint8List.fromList([0xff]));
    });

    test('encodes double', () {
      final result = codec.encode(3.14);
      expect(result[0], 0xcb); // float 64 format
      expect(result.length, 9);
    });

    test('encodes string', () {
      final result = codec.encode('hello');
      expect(result[0], 0xa5); // fixstr with length 5
      expect(result.sublist(1), 'hello'.codeUnits);
    });

    test('encodes binary data', () {
      final data = Uint8List.fromList([1, 2, 3]);
      final result = codec.encode(data);
      expect(result[0], 0xc4); // bin 8 format
      expect(result[1], 3); // length
      expect(result.sublist(2), [1, 2, 3]);
    });

    test('encodes list', () {
      final result = codec.encode([1, 2, 3]);
      expect(result[0], 0x93); // fixarray with 3 elements
      expect(result.sublist(1), [1, 2, 3]);
    });

    test('encodes map', () {
      final result = codec.encode({'a': 1});
      expect(result[0], 0x81); // fixmap with 1 entry
    });

    test('encodes empty list', () {
      final result = codec.encode([]);
      expect(result, Uint8List.fromList([0x90])); // fixarray with 0 elements
    });

    test('encodes empty map', () {
      final result = codec.encode({});
      expect(result, Uint8List.fromList([0x80])); // fixmap with 0 entries
    });

    test('encodes nested structures', () {
      final data = {
        'name': 'Alice',
        'age': 30,
        'hobbies': ['reading', 'coding'],
      };
      final result = codec.encode(data);
      expect(result.isNotEmpty, isTrue);
      expect(result[0] & 0xf0, 0x80); // fixmap format
    });
  });

  group('MessagePackCodec decoding', () {
    const codec = MessagePackCodec();

    test('decodes null', () {
      final data = Uint8List.fromList([0xc0]);
      final result = codec.decode(data);
      expect(result, isNull);
    });

    test('decodes bool true', () {
      final data = Uint8List.fromList([0xc3]);
      final result = codec.decode(data);
      expect(result, isTrue);
    });

    test('decodes bool false', () {
      final data = Uint8List.fromList([0xc2]);
      final result = codec.decode(data);
      expect(result, isFalse);
    });

    test('decodes positive integer', () {
      final data = Uint8List.fromList([0x2a]);
      final result = codec.decode(data);
      expect(result, 42);
    });

    test('decodes negative integer', () {
      final data = Uint8List.fromList([0xff]);
      final result = codec.decode(data);
      expect(result, -1);
    });

    test('decodes string', () {
      final data = Uint8List.fromList([0xa5, ...('hello'.codeUnits)]);
      final result = codec.decode(data);
      expect(result, 'hello');
    });

    test('decodes binary data', () {
      final data = Uint8List.fromList([0xc4, 3, 1, 2, 3]);
      final result = codec.decode(data);
      expect(result, isA<Uint8List>());
      expect(result! as Uint8List, [1, 2, 3]);
    });

    test('decodes list', () {
      final data = Uint8List.fromList([0x93, 1, 2, 3]);
      final result = codec.decode(data);
      expect(result, isA<List>());
      expect(result! as List, [1, 2, 3]);
    });

    test('decodes map', () {
      final data = Uint8List.fromList([0x81, 0xa1, 0x61, 1]); // {'a': 1}
      final result = codec.decode(data);
      expect(result, isA<Map>());
      expect((result! as Map)['a'], 1);
    });

    test('decodes empty list', () {
      final data = Uint8List.fromList([0x90]);
      final result = codec.decode(data);
      expect(result, isA<List>());
      expect((result! as List).isEmpty, isTrue);
    });

    test('decodes empty map', () {
      final data = Uint8List.fromList([0x80]);
      final result = codec.decode(data);
      expect(result, isA<Map>());
      expect((result! as Map).isEmpty, isTrue);
    });
  });

  group('MessagePackCodec round-trip', () {
    const codec = MessagePackCodec();

    test('round-trips null', () {
      final encoded = codec.encode(null);
      final decoded = codec.decode(encoded);
      expect(decoded, isNull);
    });

    test('round-trips bool', () {
      final encoded = codec.encode(true);
      final decoded = codec.decode(encoded);
      expect(decoded, isTrue);
    });

    test('round-trips integer', () {
      final encoded = codec.encode(12345);
      final decoded = codec.decode(encoded);
      expect(decoded, 12345);
    });

    test('round-trips double', () {
      final encoded = codec.encode(3.14159);
      final decoded = codec.decode(encoded);
      expect(decoded, closeTo(3.14159, 0.00001));
    });

    test('round-trips string', () {
      final encoded = codec.encode('Hello, MessagePack!');
      final decoded = codec.decode(encoded);
      expect(decoded, 'Hello, MessagePack!');
    });

    test('round-trips binary data', () {
      final original = Uint8List.fromList([0, 1, 2, 3, 4, 5]);
      final encoded = codec.encode(original);
      final decoded = codec.decode(encoded)! as Uint8List;
      expect(decoded, original);
    });

    test('round-trips list', () {
      final original = [1, 'two', 3.0, true, null];
      final encoded = codec.encode(original);
      final decoded = codec.decode(encoded)! as List;
      expect(decoded, original);
    });

    test('round-trips map', () {
      final original = {
        'int': 42,
        'string': 'value',
        'double': 3.14,
        'bool': true,
        'null': null,
      };
      final encoded = codec.encode(original);
      final decoded = codec.decode(encoded)! as Map;
      expect(decoded['int'], original['int']);
      expect(decoded['string'], original['string']);
      expect(decoded['double'], closeTo(3.14, 0.01));
      expect(decoded['bool'], original['bool']);
      expect(decoded['null'], original['null']);
    });

    test('round-trips nested structures', () {
      final original = {
        'user': {
          'name': 'Alice',
          'age': 30,
          'tags': ['developer', 'dart'],
        },
        'scores': [95, 87, 92],
      };
      final encoded = codec.encode(original);
      final decoded = codec.decode(encoded)! as Map;
      final user = decoded['user'] as Map;

      expect(user['name'], 'Alice');
      expect(user['age'], 30);
      expect(user['tags'], ['developer', 'dart']);
      expect(decoded['scores'], [95, 87, 92]);
    });
  });

  group('MessagePackCodec with registry', () {
    test('encodes and decodes with custom extension', () {
      final registry = MessagePackRegistry()
        ..register(
          MessagePackExtension.create<CustomExtension>(
            typeId: 42,
            encoder: (obj, reg) => obj.data,
            decoder: (data, reg) => CustomExtension(42, data),
          ),
        );
      final codec = MessagePackCodec(registry: registry);

      final custom = CustomExtension(42, Uint8List.fromList([1, 2, 3]));
      final encoded = codec.encode(custom);
      final decoded = codec.decode(encoded)! as CustomExtension;

      expect(decoded, isA<CustomExtension>());
      expect(decoded.type, 42);
      expect(decoded.data, [1, 2, 3]);
    });
  });

  group('msgpack constant', () {
    test('is a MessagePackCodec instance', () {
      expect(msgpack, isA<MessagePackCodec>());
    });

    test('has null registry', () {
      expect(msgpack.registry, isNull);
    });

    test('has default buffer size', () {
      expect(msgpack.defaultBufferSize, 1024);
    });

    test('can encode data', () {
      final result = msgpack.encode({'key': 'value'});
      expect(result, isA<Uint8List>());
      expect(result.isNotEmpty, isTrue);
    });

    test('can decode data', () {
      final encoded = msgpack.encode({'key': 'value'});
      final decoded = msgpack.decode(encoded)! as Map;
      expect(decoded['key'], 'value');
    });
  });

  group('MessagePackObjectX extension', () {
    test('encodes null', () {
      final result = null.encode();
      expect(result, Uint8List.fromList([0xc0]));
    });

    test('encodes int', () {
      final result = 42.encode();
      expect(result[0], 0x2a);
    });

    test('encodes string', () {
      final result = 'test'.encode();
      expect(result[0], 0xa4);
    });

    test('encodes list', () {
      final result = [1, 2, 3].encode();
      expect(result[0], 0x93);
    });

    test('encodes map', () {
      final result = {'key': 'value'}.encode();
      expect(result[0] & 0xf0, 0x80);
    });

    test('uses custom codec when provided', () {
      final registry = MessagePackRegistry();
      final codec = MessagePackCodec(
        registry: registry,
        defaultBufferSize: 2048,
      );
      final result = 'test'.encode(codec: codec);
      expect(result, isA<Uint8List>());
    });
  });

  group('MessagePackBinaryX extension', () {
    test('decodes to correct type', () {
      final data = Uint8List.fromList([0xc0]);
      final result = data.decode();
      expect(result, isNull);
    });

    test('decodes with type parameter', () {
      final encoded = msgpack.encode({'key': 'value'});
      final result = encoded.decode<Map>();
      expect(result, isA<Map>());
      expect(result['key'], 'value');
    });

    test('decodes list with type parameter', () {
      final encoded = msgpack.encode([1, 2, 3]);
      final result = encoded.decode<List>();
      expect(result, isA<List>());
      expect(result, [1, 2, 3]);
    });

    test('uses custom codec when provided', () {
      final registry = MessagePackRegistry();
      final codec = MessagePackCodec(registry: registry);
      final encoded = codec.encode('test');
      final result = encoded.decode(codec: codec);
      expect(result, 'test');
    });
  });

  group('MessagePackCodec with different buffer sizes', () {
    test('small buffer size works correctly', () {
      const codec = MessagePackCodec(defaultBufferSize: 16);
      final largeData = List.generate(100, (i) => i);
      final encoded = codec.encode(largeData);
      final decoded = codec.decode(encoded)! as List;
      expect(decoded, largeData);
    });

    test('large buffer size works correctly', () {
      const codec = MessagePackCodec(defaultBufferSize: 8192);
      final smallData = [1, 2, 3];
      final encoded = codec.encode(smallData);
      final decoded = codec.decode(encoded)! as List;
      expect(decoded, smallData);
    });
  });

  group('MessagePackCodec edge cases', () {
    const codec = MessagePackCodec();

    test('handles large integers', () {
      const value = 9223372036854775807; // max int64
      final encoded = codec.encode(value);
      final decoded = codec.decode(encoded);
      expect(decoded, value);
    });

    test('handles large negative integers', () {
      const value = -9223372036854775808; // min int64
      final encoded = codec.encode(value);
      final decoded = codec.decode(encoded);
      expect(decoded, value);
    });

    test('handles empty string', () {
      final encoded = codec.encode('');
      final decoded = codec.decode(encoded);
      expect(decoded, '');
    });

    test('handles unicode string', () {
      const value = '你好世界 🌍';
      final encoded = codec.encode(value);
      final decoded = codec.decode(encoded);
      expect(decoded, value);
    });

    test('handles deeply nested structures', () {
      final value = {
        'level1': {
          'level2': {
            'level3': {
              'level4': ['deep', 'nested', 'data'],
            },
          },
        },
      };
      final encoded = codec.encode(value);
      final decoded = codec.decode(encoded)! as Map;
      final level1 = decoded['level1'] as Map;
      final level2 = level1['level2'] as Map;
      final level3 = level2['level3'] as Map;
      expect(level3['level4'], [
        'deep',
        'nested',
        'data',
      ]);
    });

    test('handles mixed types in list', () {
      final value = [
        1,
        'string',
        3.14,
        true,
        null,
        [1, 2],
        {'key': 'value'},
      ];
      final encoded = codec.encode(value);
      final decoded = codec.decode(encoded)! as List;
      expect(decoded[0], 1);
      expect(decoded[1], 'string');
      expect(decoded[2], closeTo(3.14, 0.01));
      expect(decoded[3], true);
      expect(decoded[4], null);
      expect(decoded[5], [1, 2]);
      expect((decoded[6] as Map)['key'], 'value');
    });

    test('handles mixed types in map', () {
      final value = {
        'int': 1,
        'string': 'test',
        'double': 3.14,
        'bool': true,
        'null': null,
        'list': [1, 2],
        'map': {'nested': 'value'},
      };
      final encoded = codec.encode(value);
      final decoded = codec.decode(encoded)! as Map;
      expect(decoded['int'], 1);
      expect(decoded['string'], 'test');
      expect(decoded['double'], closeTo(3.14, 0.01));
      expect(decoded['bool'], true);
      expect(decoded['null'], null);
      expect(decoded['list'], [1, 2]);
      expect((decoded['map'] as Map)['nested'], 'value');
    });
  });
}

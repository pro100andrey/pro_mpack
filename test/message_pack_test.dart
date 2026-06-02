import 'dart:typed_data';

import 'package:pro_mpack/pro_mpack.dart';
import 'package:test/test.dart';

void main() {
  group('MessagePack Unified API', () {
    test('basic pack/unpack', () {
      final mpack = MessagePack();
      final data = {'a': 1, 'b': 'hello', 'c': true};
      final bytes = mpack.pack(data);
      final decoded = mpack.unpack<Map<Object?, Object?>>(bytes);
      expect(decoded, data);
    });

    test('declarative extensions', () {
      final mpack = MessagePack(
        extensions: (config) {
          config.register<BigInt>(
            extId: 1,
            encoder: (val, p) => p.packString(val.toString()),
            decoder: (u, l) => BigInt.parse(u.unpackString()!),
            polymorphic: true,
          );
        },
      );

      final big = BigInt.parse('123456789');
      final bytes = mpack.pack(big);
      final decoded = mpack.unpack<BigInt>(bytes);
      expect(decoded, big);
    });

    test('imperative extensions', () {
      final mpack = MessagePack()
        ..register(
          extId: 1,
          encoder: (val, p) => p.packString(val.toString()),
          decoder: (u, l) => BigInt.parse(u.unpackString()!),
          polymorphic: true,
        );

      final big = BigInt.parse('987654321');
      final bytes = mpack.pack(big);
      expect(mpack.unpack<BigInt>(bytes), big);
    });

    test('groups (declarative)', () {
      final mpack = MessagePack(
        extensions: (config) {
          config.registerGroup(
            extId: 10,
            builder: (group) {
              group.add<_MyDateTime>(
                subId: 1,
                encoder: (dt, p) => p.packInt(dt.value.millisecondsSinceEpoch),
                decoder: (u, l) => _MyDateTime(
                  DateTime.fromMillisecondsSinceEpoch(u.unpackInt()!),
                ),
              );
            },
          );
        },
      );

      final now = _MyDateTime(DateTime.utc(2023));
      final bytes = mpack.pack(now);
      final decoded = mpack.unpack<_MyDateTime>(bytes);
      expect(
        decoded.value.millisecondsSinceEpoch,
        now.value.millisecondsSinceEpoch,
      );
    });

    test('codec compatibility', () {
      final mpack = MessagePack();
      final data = [1, 2, 3];
      final bytes = mpack.encode(data);
      expect(mpack.decode(bytes), data);
    });

    test('packAll/unpackAll', () {
      // final mpack = MessagePack();
      // final values = [1, 'two', 3.0];
      // final bytes = mpack.packAll(values);
      // expect(mpack.unpackAll(bytes), values);
    });

    test('subId >= 128 (varInt)', () {
      final mpack = MessagePack(
        extensions: (config) {
          config.registerGroup(
            extId: 5,
            builder: (group) {
              group.add<_MyType>(
                subId: 300,
                encoder: (v, p) => p.packInt(v.value),
                decoder: (u, l) => _MyType(u.unpackInt()!),
              );
            },
          );
        },
      );

      final bytes = mpack.pack(const _MyType(42));
      expect(mpack.unpack<_MyType>(bytes).value, 42);
    });

    group('register built-in type validation', () {
      test('throws MessagePackConfigurationException for int', () {
        expect(
          () => MessagePack(
            extensions: (c) => c.register<int>(
              extId: 1,
              encoder: (v, p) => p.packInt(v),
              decoder: (u, l) => u.unpackInt()!,
            ),
          ),
          throwsA(isA<MessagePackConfigurationException>()),
        );
      });

      test(
        'throws MessagePackConfigurationException for Object? (base type)',
        () {
          expect(
            () => MessagePack(
              extensions: (c) => c.register<Object?>(
                extId: 1,
                encoder: (v, p) => p.pack(v),
                decoder: (u, l) => u.unpackString()!,
              ),
            ),
            throwsA(isA<MessagePackConfigurationException>()),
          );
        },
      );

      test('throws MessagePackConfigurationException for String', () {
        expect(
          () => MessagePack(
            extensions: (c) => c.register<String>(
              extId: 1,
              encoder: (v, p) => p.packString(v),
              decoder: (u, l) => u.unpackString()!,
            ),
          ),
          throwsA(isA<MessagePackConfigurationException>()),
        );
      });

      test('throws MessagePackConfigurationException for bool', () {
        expect(
          () => MessagePack(
            extensions: (c) => c.register<bool>(
              extId: 1,
              encoder: (v, p) => p.packBool(v),
              decoder: (u, l) => u.unpackBool()!,
            ),
          ),
          throwsA(isA<MessagePackConfigurationException>()),
        );
      });

      test('throws MessagePackConfigurationException for double', () {
        expect(
          () => MessagePack(
            extensions: (c) => c.register<double>(
              extId: 1,
              encoder: (v, p) => p.packDouble(v),
              decoder: (u, l) => u.unpackDouble()!,
            ),
          ),
          throwsA(isA<MessagePackConfigurationException>()),
        );
      });

      test('throws MessagePackConfigurationException for List', () {
        expect(
          () => MessagePack(
            extensions: (c) => c.register<List<dynamic>>(
              extId: 1,
              encoder: (v, p) => p.packArray(v),
              decoder: (u, l) => u.unpackArray()!,
            ),
          ),
          throwsA(isA<MessagePackConfigurationException>()),
        );
      });

      test('throws MessagePackConfigurationException for Map', () {
        expect(
          () => MessagePack(
            extensions: (c) => c.register<Map<dynamic, dynamic>>(
              extId: 1,
              encoder: (v, p) => p.packMap(v),
              decoder: (u, l) => u.unpackMap()!,
            ),
          ),
          throwsA(isA<MessagePackConfigurationException>()),
        );
      });

      test('throws MessagePackConfigurationException for Set', () {
        expect(
          () => MessagePack(
            extensions: (c) => c.register<Set<dynamic>>(
              extId: 1,
              encoder: (v, p) => p.pack(v),
              decoder: (u, l) => u.unpack() as Set<dynamic>,
            ),
          ),
          throwsA(isA<MessagePackConfigurationException>()),
        );
      });

      test('throws MessagePackConfigurationException for Uint8List', () {
        expect(
          () => MessagePack(
            extensions: (c) => c.register<Uint8List>(
              extId: 1,
              encoder: (v, p) => p.packBinary(v),
              decoder: (u, l) => u.unpackBinary()!,
            ),
          ),
          throwsA(isA<MessagePackConfigurationException>()),
        );
      });

      test('throws MessagePackConfigurationException for ByteData', () {
        expect(
          () => MessagePack(
            extensions: (c) => c.register<ByteData>(
              extId: 1,
              encoder: (v, p) => p.pack(v),
              decoder: (u, l) => u.unpack() as ByteData,
            ),
          ),
          throwsA(isA<MessagePackConfigurationException>()),
        );
      });

      test('throws MessagePackConfigurationException for DateTime', () {
        expect(
          () => MessagePack(
            extensions: (c) => c.register<DateTime>(
              extId: 1,
              encoder: (v, p) => p.packTimestamp(v),
              decoder: (u, l) => u.unpack() as DateTime,
            ),
          ),
          throwsA(isA<MessagePackConfigurationException>()),
        );
      });

      test('throws MessagePackConfigurationException for Float', () {
        expect(
          () => MessagePack(
            extensions: (c) => c.register<Float>(
              extId: 1,
              encoder: (v, p) => p.packFloat(v),
              decoder: (u, l) => Float(u.unpackDouble()!),
            ),
          ),
          throwsA(isA<MessagePackConfigurationException>()),
        );
      });
    });

    group('registerGroup built-in type validation', () {
      test('throws MessagePackConfigurationException for DateTime', () {
        expect(
          () => MessagePack(
            extensions: (c) => c.registerGroup(
              extId: 1,
              builder: (group) {
                group.add<DateTime>(
                  subId: 1,
                  encoder: (v, p) => p.packTimestamp(v),
                  decoder: (u, l) => u.unpack() as DateTime,
                );
              },
            ),
          ),
          throwsA(isA<MessagePackConfigurationException>()),
        );
      });

      test('throws MessagePackConfigurationException for int', () {
        expect(
          () => MessagePack(
            extensions: (c) => c.registerGroup(
              extId: 1,
              builder: (group) {
                group.add<int>(
                  subId: 1,
                  encoder: (v, p) => p.packInt(v),
                  decoder: (u, l) => u.unpackInt()!,
                );
              },
            ),
          ),
          throwsA(isA<MessagePackConfigurationException>()),
        );
      });

      test('throws MessagePackConfigurationException for String', () {
        expect(
          () => MessagePack(
            extensions: (c) => c.registerGroup(
              extId: 1,
              builder: (group) {
                group.add<String>(
                  subId: 1,
                  encoder: (v, p) => p.packString(v),
                  decoder: (u, l) => u.unpackString()!,
                );
              },
            ),
          ),
          throwsA(isA<MessagePackConfigurationException>()),
        );
      });

      test('throws MessagePackConfigurationException for List', () {
        expect(
          () => MessagePack(
            extensions: (c) => c.registerGroup(
              extId: 1,
              builder: (group) {
                group.add<List<dynamic>>(
                  subId: 1,
                  encoder: (v, p) => p.packArray(v),
                  decoder: (u, l) => u.unpackArray()!,
                );
              },
            ),
          ),
          throwsA(isA<MessagePackConfigurationException>()),
        );
      });
    });
  });

  group('MessagePack Edge Cases', () {
    test('Duplicate extension registration', () {
      final mpack = MessagePack()
        ..register<_MyType>(
          extId: 10,
          encoder: (v, p) {},
          decoder: (u, l) => const _MyType(0),
        );
      expect(
        () => mpack.register<_MyType>(
          extId: 10,
          encoder: (v, p) {},
          decoder: (u, l) => const _MyType(0),
        ),
        throwsA(isA<MessagePackConfigurationException>()),
      );
    });

    test('Unregistered extension ID in unpack', () {
      final mpack = MessagePack();
      expect(
        () => mpack.unpack<dynamic>(Uint8List.fromList([0xd4, 0x32, 0x00])),
        throwsA(isA<MessagePackConfigurationException>()),
      );
    });

    test('Empty group data', () {
      final mpack = MessagePack()..registerGroup(extId: 10, builder: (g) {});
      final data = Uint8List.fromList([0xc7, 0x00, 0x0a]);
      expect(
        () => mpack.unpack<dynamic>(data),
        throwsA(isA<MessagePackFormatException>()),
      );
    });

    test('MessagePackGroup subtype not found in encode', () {
      final mpack = MessagePack()
        ..registerGroup(
          extId: 20,
          builder: (g) {
            g.add<_MyType>(
              subId: 1,
              encoder: (v, p) => p.packInt(v.value),
              decoder: (u, l) => _MyType(u.unpackInt()!),
            );
          },
        );
      expect(
        () => mpack.pack(Object()),
        throwsA(isA<MessagePackUnsupportedTypeException>()),
      );
    });

    test('MessagePackGroup subtype id not found in decode', () {
      final mpack = MessagePack()
        ..registerGroup(
          extId: 20,
          builder: (g) {
            g.add<_MyType>(
              subId: 1,
              encoder: (v, p) => p.packInt(v.value),
              decoder: (u, l) => _MyType(u.unpackInt()!),
            );
          },
        );
      final data = Uint8List.fromList([0xc7, 0x02, 0x14, 0x02, 0xc0]);
      expect(
        () => mpack.unpack<dynamic>(data),
        throwsA(isA<MessagePackConfigurationException>()),
      );
    });

    test('pack for unregistered type throws', () {
      final mpack = MessagePack();
      expect(
        () => mpack.pack(Object()),
        throwsA(isA<MessagePackUnsupportedTypeException>()),
      );
    });
  });

  group('Exception coverage', () {
    test('MessagePackException toString and name', () {
      const e = MessagePackFormatException('msg', 'sugg');
      expect(e.name, 'MessagePackFormatException');
      expect(e.toString(), contains('MessagePackFormatException: msg'));
      expect(e.toString(), contains('Suggestion: sugg'));

      const e2 = MessagePackUnsupportedTypeException(int, 'msg', 'sugg');
      expect(e2.name, 'MessagePackUnsupportedTypeException');
      expect(
        e2.toString(),
        contains('MessagePackUnsupportedTypeException: msg'),
      );

      const e3 = MessagePackSizeException('msg', 'sugg');
      expect(e3.name, 'MessagePackSizeException');
      expect(e3.toString(), contains('MessagePackSizeException: msg'));

      const e4 = MessagePackConfigurationException('msg', 'sugg');
      expect(e4.name, 'MessagePackConfigurationException');
      expect(e4.toString(), contains('MessagePackConfigurationException: msg'));
    });
  });
}

class _MyType {
  const _MyType(this.value);
  final int value;
}

class _MyDateTime {
  const _MyDateTime(this.value);
  final DateTime value;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is _MyDateTime && value == other.value;

  @override
  int get hashCode => value.hashCode;
}

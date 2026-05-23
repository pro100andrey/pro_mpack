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
            encoder: (val, ctx) => ctx.pack(val.toString()),
            decoder: (data, ctx) => BigInt.parse(ctx.unpack<String>(data)),
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
          encoder: (val, ctx) => ctx.pack(val.toString()),
          decoder: (data, ctx) => BigInt.parse(ctx.unpack<String>(data)),
        );

      final big = BigInt.parse('987654321');
      final bytes = mpack.pack(big);
      expect(mpack.unpack<BigInt>(bytes), big);
    });

    test('groups (declarative)', () {
      final mpack = MessagePack(
        extensions: (config) {
          config.registerGroup<_MyDateTime>(
            extId: 10,
            builder: (group) {
              group.add<_MyDateTime>(
                subId: 1,
                encoder: (dt, ctx) => ctx.pack(dt.value.millisecondsSinceEpoch),
                decoder: (data, ctx) => _MyDateTime(
                  DateTime.fromMillisecondsSinceEpoch(ctx.unpack<int>(data)),
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
      final mpack = MessagePack();
      final values = [1, 'two', 3.0];
      final bytes = mpack.packAll(values);
      expect(mpack.unpackAll<Object?>(bytes), values);
    });

    test('subId >= 128 (varInt)', () {
      final mpack = MessagePack(
        extensions: (config) {
          config.registerGroup<_MyType>(
            extId: 5,
            builder: (group) {
              group.add<_MyType>(
                subId: 300,
                encoder: (v, ctx) => ctx.pack(v.value),
                decoder: (d, ctx) => _MyType(ctx.unpack<int>(d)),
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
              encoder: (v, ctx) => ctx.pack(v),
              decoder: (d, ctx) => ctx.unpack<int>(d),
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
                encoder: (v, ctx) => ctx.pack(v),
                decoder: (d, ctx) => ctx.unpack<String>(d),
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
              encoder: (v, ctx) => ctx.pack(v),
              decoder: (d, ctx) => ctx.unpack<String>(d),
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
              encoder: (v, ctx) => ctx.pack(v),
              decoder: (d, ctx) => ctx.unpack<bool>(d),
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
              encoder: (v, ctx) => ctx.pack(v),
              decoder: (d, ctx) => ctx.unpack<double>(d),
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
              encoder: (v, ctx) => ctx.pack(v),
              decoder: (d, ctx) => ctx.unpack<List<dynamic>>(d),
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
              encoder: (v, ctx) => ctx.pack(v),
              decoder: (d, ctx) => ctx.unpack<Map<dynamic, dynamic>>(d),
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
              encoder: (v, ctx) => ctx.pack(v),
              decoder: (d, ctx) => ctx.unpack<Set<dynamic>>(d),
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
              encoder: (v, ctx) => ctx.pack(v),
              decoder: (d, ctx) => ctx.unpack<Uint8List>(d),
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
              encoder: (v, ctx) => ctx.pack(v),
              decoder: (d, ctx) => ctx.unpack<ByteData>(d),
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
              encoder: (v, ctx) => ctx.pack(v),
              decoder: (d, ctx) => ctx.unpack<DateTime>(d),
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
              encoder: (v, ctx) => ctx.pack(v.value),
              decoder: (d, ctx) => Float(ctx.unpack<double>(d)),
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
            extensions: (c) => c.registerGroup<DateTime>(
              extId: 1,
              builder: (group) {
                group.add<DateTime>(
                  subId: 1,
                  encoder: (v, ctx) => ctx.pack(v),
                  decoder: (d, ctx) => ctx.unpack<DateTime>(d),
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
            extensions: (c) => c.registerGroup<int>(
              extId: 1,
              builder: (group) {
                group.add<int>(
                  subId: 1,
                  encoder: (v, ctx) => ctx.pack(v),
                  decoder: (d, ctx) => ctx.unpack<int>(d),
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
            extensions: (c) => c.registerGroup<String>(
              extId: 1,
              builder: (group) {
                group.add<String>(
                  subId: 1,
                  encoder: (v, ctx) => ctx.pack(v),
                  decoder: (d, ctx) => ctx.unpack<String>(d),
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
            extensions: (c) => c.registerGroup<List<dynamic>>(
              extId: 1,
              builder: (group) {
                group.add<List<dynamic>>(
                  subId: 1,
                  encoder: (v, ctx) => ctx.pack(v),
                  decoder: (d, ctx) => ctx.unpack<List<dynamic>>(d),
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
          encoder: (v, ctx) => Uint8List(0),
          decoder: (d, ctx) => const _MyType(0),
        );
      expect(
        () => mpack.register<_MyType>(
          extId: 10,
          encoder: (v, ctx) => Uint8List(0),
          decoder: (d, ctx) => const _MyType(0),
        ),
        throwsA(isA<MessagePackConfigurationException>()),
      );
    });

    test('Unregistered extension ID in decodeObject', () {
      final mpack = MessagePack();
      expect(
        () => mpack.decodeObject(50, Uint8List(0)),
        throwsA(isA<MessagePackConfigurationException>()),
      );
    });

    test('Empty group data', () {
      final mpack = MessagePack()
        ..registerGroup<Object>(extId: 10, builder: (g) {});
      final data = Uint8List.fromList([0xc7, 0x00, 0x0a]);
      expect(
        () => mpack.unpack<dynamic>(data),
        throwsA(isA<MessagePackConfigurationException>()),
      );
    });

    test('MessagePackGroup subtype not found in encode', () {
      final mpack = MessagePack()
        ..registerGroup<Object>(
          extId: 20,
          builder: (g) {
            g.add<int>(
              subId: 1,
              encoder: (v, ctx) => ctx.pack(null),
              decoder: (d, ctx) => 0,
            );
          },
        );
      expect(
        () => mpack.pack(const _MyType(1)),
        throwsA(isA<MessagePackConfigurationException>()),
      );
    });

    test('MessagePackGroup subtype id not found in decode', () {
      final mpack = MessagePack()
        ..registerGroup<Object>(
          extId: 20,
          builder: (g) {
            g.add<int>(
              subId: 1,
              encoder: (v, ctx) => ctx.pack(null),
              decoder: (d, ctx) => 0,
            );
          },
        );
      final data = Uint8List.fromList([0xc7, 0x02, 0x14, 0x02, 0xc0]);
      expect(
        () => mpack.unpack<dynamic>(data),
        throwsA(isA<MessagePackConfigurationException>()),
      );
    });

    test('extTypeForObject for null', () {
      final mpack = MessagePack();
      expect(mpack.extTypeForObject(null), isNull);
    });

    test('encodeObject for unregistered type', () {
      final mpack = MessagePack();
      expect(
        () => mpack.encodeObject(Object()),
        throwsA(isA<MessagePackUnsupportedTypeException>()),
      );
    });

    test('MessagePackContext implements', () {
      const ctx = _FakeContext();
      expect(ctx, isA<MessagePackContext>());
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

class _FakeContext implements MessagePackContext {
  const _FakeContext();
  @override
  Uint8List pack<T>(T value) => throw UnimplementedError();
  @override
  Uint8List packAll<T>(Iterable<T> values) => throw UnimplementedError();
  @override
  T unpack<T>(Uint8List data) => throw UnimplementedError();
  @override
  List<T> unpackAll<T>(Uint8List data) => throw UnimplementedError();
}

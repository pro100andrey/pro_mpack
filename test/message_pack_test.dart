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
            decoder: (data, ctx) => BigInt.parse(ctx.unpack<String>(data)!),
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
        ..register<BigInt>(
          extId: 1,
          encoder: (val, ctx) => ctx.pack(val.toString()),
          decoder: (data, ctx) => BigInt.parse(ctx.unpack<String>(data)!),
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
              group.add<DateTime>(
                typeId: 1,
                encoder: (dt, ctx) => ctx.pack(dt.millisecondsSinceEpoch),
                decoder: (data, ctx) => DateTime.fromMillisecondsSinceEpoch(
                  ctx.unpack<int>(data)!,
                ),
              );
            },
          );
        },
      );

      final now = DateTime.now();
      final bytes = mpack.pack(now);
      final decoded = mpack.unpack<DateTime>(bytes);
      expect(decoded?.millisecondsSinceEpoch, now.millisecondsSinceEpoch);
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
      expect(mpack.unpackAll(bytes), values);
    });
  });
}

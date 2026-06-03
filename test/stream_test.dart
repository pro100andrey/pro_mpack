import 'dart:async';
import 'dart:typed_data';

import 'package:pro_mpack/pro_mpack.dart';
import 'package:test/test.dart';

class Point {
  Point(this.x, this.y);

  final int x;
  final int y;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Point &&
          runtimeType == other.runtimeType &&
          x == other.x &&
          y == other.y;

  @override
  int get hashCode => x.hashCode ^ y.hashCode;
}

void main() {
  group('MessagePackStreamTransformer', () {
    late MessagePack mp;

    setUp(() {
      mp = MessagePack();
    });

    test('decodes simple streaming values', () async {
      final controller = StreamController<List<int>>();
      final stream = controller.stream.transform(mp.streamDecoder);

      final results = <dynamic>[];
      final subscription = stream.listen(results.add);

      controller
        ..add(mp.pack(123))
        ..add(mp.pack('hello'))
        ..add(mp.pack([1, 2, 3]));

      await controller.close();
      await subscription.cancel();

      expect(results, [
        123,
        'hello',
        [1, 2, 3],
      ]);
    });

    test('decodes values split across chunks', () async {
      final controller = StreamController<List<int>>();
      final stream = controller.stream.transform(mp.streamDecoder);

      final results = <dynamic>[];
      final subscription = stream.listen(results.add);

      final payload1 = mp.pack('this is a relatively long string');
      final payload2 = mp.pack({
        'key': 'value',
        'nested': [1, 2, 3],
      });

      final combined = Uint8List.fromList([...payload1, ...payload2]);

      // Feed byte by byte to force edge cases in the scanner
      for (final byte in combined) {
        controller.add([byte]);
        await Future<dynamic>.delayed(Duration.zero); // yield to event loop
      }

      await controller.close();
      await subscription.cancel();

      expect(results, [
        'this is a relatively long string',
        {
          'key': 'value',
          'nested': [1, 2, 3],
        },
      ]);
    });

    test('recovers from incomplete chunks gracefully', () async {
      final controller = StreamController<List<int>>();
      final stream = controller.stream.transform(mp.streamDecoder);

      final results = <dynamic>[];
      final subscription = stream.listen(results.add);

      final payload = mp.pack(List.generate(100, (i) => i));

      // Split payload in half
      final half = payload.length ~/ 2;

      controller.add(payload.sublist(0, half));
      await Future<dynamic>.delayed(const Duration(milliseconds: 10));
      expect(results, isEmpty, reason: 'Should not emit partial array');

      controller.add(payload.sublist(half));
      await controller.close();
      await subscription.cancel();

      expect(results, hasLength(1));
      expect(results.first, hasLength(100));
    });

    test('handles custom extensions in stream', () async {
      final mpCustom = MessagePack(
        extensions: (mp) {
          mp.register<Point>(
            extId: 10,
            encoder: (p, pk) {
              pk
                ..packInt(p.x)
                ..packInt(p.y);
            },
            decoder: (u, l) {
              final x = u.unpackInt()!;
              final y = u.unpackInt()!;
              return Point(x, y);
            },
          );
        },
      );

      final controller = StreamController<List<int>>();
      final stream = controller.stream.transform(mpCustom.streamDecoder);

      final results = <dynamic>[];
      final subscription = stream.listen(results.add);

      final point = Point(10, 20);
      final payload = mpCustom.pack(point);

      controller.add(payload);
      await controller.close();
      await subscription.cancel();

      expect(results, [point]);
    });
  });
}

import 'dart:io';

import 'package:pro_mpack/pro_mpack.dart';

// A custom class we want to serialize natively
class Point {
  const Point(this.x, this.y);

  final int x;
  final int y;

  @override
  String toString() => 'Point(x: $x, y: $y)';
}

void main() {
  _log('--- Extensions pro_mpack Example ---');

  // Create a reusable MessagePack instance and register extensions.
  // This is highly recommended for performance (O(1) lookups).
  final mp = MessagePack(
    extensions: (mp) {
      mp.register<Point>(
        // MessagePack extension types can be from 0 to 127
        extId: 42,

        // Custom encoder
        encoder: (point, packer) {
          packer
            ..packInt(point.x)
            ..packInt(point.y);
        },

        // Custom decoder
        decoder: (unpacker, length) {
          final x = unpacker.unpackInt()!;
          final y = unpacker.unpackInt()!;
          return Point(x, y);
        },
      );
    },
  );

  const myPoint = Point(1920, 1080);

  // We can also nest our custom type inside standard collections
  final payload = {
    'resolution': myPoint,
    'description': 'Full HD',
  };

  _log('\nOriginal Payload:');
  _log(payload);

  final bytes = mp.pack(payload);
  _log('\nSerialized Bytes (Notice the extension bytes):');
  _log(bytes);

  final decoded = mp.unpack<Map<dynamic, dynamic>>(bytes);
  _log('\nDecoded Payload (Point object restored perfectly!):');
  _log(decoded);
  _log('Type of resolution: ${decoded['resolution'].runtimeType}');
}

void _log([Object? object = '']) => stdout.writeln(object);

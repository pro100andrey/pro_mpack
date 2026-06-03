import 'dart:io';
import 'package:pro_mpack/pro_mpack.dart';

void main() {
  _log('--- Basic pro_mpack Example ---');

  // 1. Serialize standard types
  final data = {
    'name': 'Dart',
    'version': 3.5,
    'isAwesome': true,
    'tags': ['fast', 'cross-platform', 'typesafe'],
  };

  _log('\nOriginal Data:');
  _log(data);

  // Serialize to MessagePack binary format
  final bytes = serialize(data);
  _log('\nSerialized Bytes (length: ${bytes.length}):');
  _log(bytes);

  // Deserialize back to Dart objects
  final decoded = deserialize(bytes);
  _log('\nDecoded Data:');
  _log(decoded);

  // 2. High-performance caching with MessagePack instance
  // For repetitive parsing, it is recommended to create a reusable instance.
  final mp = MessagePack();

  final anotherData = [100, 200, 300, 400];
  final packedBytes = mp.pack(anotherData);
  final unpackedData = mp.unpack<List<dynamic>>(packedBytes).cast<int>();

  _log('\nUnpacked with reusable instance:');
  _log(unpackedData);
}

void _log([Object? object = '']) => stdout.writeln(object);

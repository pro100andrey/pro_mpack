// Basic usage — the core encode/decode API.
//
// Walks through serializing standard types and collections with the top-level
// `serialize`/`deserialize` functions, a reusable [MessagePack] instance for
// repeated work, and one-off custom extensions via `encodeExt`/`decodeExt`.
//
// Run: `dart run example/basic/main.dart`

import 'dart:io';

import 'package:pro_mpack/pro_mpack.dart';

class Token {
  Token(this.value);
  final String value;

  @override
  String toString() => 'Token($value)';
}

void main() {
  log('--- Basic pro_mpack Example ---');

  // 1. Serialize standard types
  final data = {
    'name': 'Dart',
    'version': 3.5,
    'isAwesome': true,
    'tags': ['fast', 'cross-platform', 'typesafe'],
  };

  log('\nOriginal Data:');
  log(data);

  // Serialize to MessagePack binary format
  final bytes = serialize(data);
  log('\nSerialized Bytes (length: ${bytes.length}):');
  log(bytes);

  // Deserialize back to Dart objects
  final decoded = deserialize(bytes);
  log('\nDecoded Data:');
  log(decoded);

  // 2. High-performance caching with MessagePack instance
  // For repetitive parsing, it is recommended to create a reusable instance.
  final mp = MessagePack();

  final anotherData = [100, 200, 300, 400];
  final packedBytes = mp.pack(anotherData);
  final unpackedData = mp.unpack<List<dynamic>>(packedBytes).cast<int>();

  log('\nUnpacked with reusable instance:');
  log(unpackedData);

  // 3. Quick Custom Extensions with Top-Level Functions
  // You can pass encodeExt and decodeExt directly to serialize/deserialize
  final token = Token('abc-123');

  final tokenBytes = serialize(
    token,
    encodeExt: (value, packer) {
      if (value is Token) {
        packer.packExt(99, (p) => p.packString(value.value));
        return true;
      }

      return false;
    },
  );

  final decodedToken = deserialize(
    tokenBytes,
    decodeExt: (extType, length, unpacker) {
      if (extType == 99) {
        return Token(unpacker.unpackString()!);
      }
      // Return null or throw if the extension type is not recognized
      return null;
    },
  );

  log('\nOne-off Extension Serialization (ExtType 99):');
  log(decodedToken);
}

void log([Object? object = '']) => stdout.writeln(object);

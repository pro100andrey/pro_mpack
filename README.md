# pro_mpack

[![pub package](https://img.shields.io/pub/v/pro_mpack.svg)](https://pub.dev/packages/pro_mpack)
[![Dart CI](https://github.com/pro100andrey/pro_mpack/actions/workflows/dart.yml/badge.svg)](https://github.com/pro100andrey/pro_mpack/actions/workflows/dart.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)

**High-performance MessagePack serializer and deserializer for Dart.**

MessagePack is an efficient binary serialization format that's smaller and faster than JSON. `pro_mpack` provides a modern, clean implementation of the [MessagePack specification](https://github.com/msgpack/msgpack/blob/master/spec.md) optimized for real-time streaming, high-frequency network protocols, and Big Data processing.

## Table of Contents

- [pro\_mpack](#pro_mpack)
  - [Table of Contents](#table-of-contents)
  - [Key Features](#key-features)
  - [Installation](#installation)
  - [Quick Start](#quick-start)
  - [Recipes \& Patterns](#recipes--patterns)
    - [1. Declarative Extensions (Recommended)](#1-declarative-extensions-recommended)
    - [2. Sub-registries (Extension Groups)](#2-sub-registries-extension-groups)
    - [3. Zero-Allocation Streaming (Async Data)](#3-zero-allocation-streaming-async-data)
    - [4. Big Data File Streaming (Batched Writes)](#4-big-data-file-streaming-batched-writes)
    - [5. Field-by-Field Codecs (Schema / Codegen)](#5-field-by-field-codecs-schema--codegen)
  - [Examples](#examples)
  - [API Overview](#api-overview)
  - [Error Handling](#error-handling)
  - [License](#license)

## Key Features

- **Extreme Performance:** Built on top of `pro_binary`. Uses `BinaryWriterPool` for zero-allocation high-frequency serialization, and encodes UTF-8 strings in a single pass.
- **Zero-Allocation Streaming:** Includes `MessagePackStreamTransformer` which seamlessly reassembles heavily fragmented network/file chunks byte-by-byte without allocating temporary garbage objects.
- **Incremental (Field-by-Field) Codecs:** Low-level `packMapLength`/`packArrayLength`, `unpackMapLength`/`unpackArrayLength`, and `Unpacker.skip()` let schema-driven code generators encode and decode structs one field at a time with the typed packers — no intermediate `Map`/`List` is built, and unknown fields are skipped for forward compatibility.
- **Seamless Extensions:** Powerful Declarative and Imperative API for custom types.
- **Extension Groups:** Bypass the strict 256-ID limit of MessagePack by grouping related sub-types logically under a single Extension ID.
- **Modern Dart 3:** Strict typing, `sealed` exception hierarchy with actionable suggestions, exhaustive pattern matching support.
- **Float Control:** Wrap `double` values in `Float` to force 32-bit serialization and save memory payload.
- **Cross-Platform:** 100% pure Dart. Works seamlessly across Native (AOT/JIT) and Web (WASM/JS).

## Installation

Add `pro_mpack` to your `pubspec.yaml`:

```yaml
dependencies:
  pro_mpack: any
```

Or add it using the command line:

```bash
dart pub add pro_mpack
```

## Quick Start

For high performance and recurring use, create a reusable `MessagePack` instance.

```dart
import 'package:pro_mpack/pro_mpack.dart';

void main() {
  final mp = MessagePack();

  final data = {
    'name': 'Dart 🚀',
    'version': 3.5,
    'tags': ['fast', 'cross-platform', 'typesafe']
  };

  // Serialize
  final bytes = mp.pack(data);
  print('Serialized to ${bytes.length} bytes');

  // Deserialize
  final decoded = mp.unpack(bytes);
  print(decoded);
}
```

For simple one-off serialization, you can use the top-level declarative functions:

```dart
final bytes = serialize({'key': 'value', 'count': 42});
final decoded = deserialize(bytes);

// They also support on-the-fly custom extensions!
final tokenBytes = serialize(
  Token('abc'),
  encodeExt: (value, packer) {
    if (value is Token) {
      packer.packExt(99, (p) => p.packString(value.value));
      return true;
    }
    return false;
  },
);
```

## Recipes & Patterns

### 1. Declarative Extensions (Recommended)

Configure your application's data protocol in one place. Perfect for complex models, third-party classes, and IoT telemetry.

```dart
final mp = MessagePack(
  extensions: (config) {
    config.register<BigInt>(
      extId: 1,
      // Use polymorphic: true for types like BigInt that hide behind internal implementations (e.g. _BigIntImpl)
      polymorphic: true,
      encoder: (number, packer) => packer.packString(number.toString()),
      decoder: (unpacker, length) => BigInt.parse(unpacker.unpackString()!),
    );
  },
);

final hugeNumber = BigInt.parse('10000000000000000000000000');
final bytes = mp.pack(hugeNumber); // Natively serialized via Extension ID 1!
```

### 2. Sub-registries (Extension Groups)

MessagePack restricts extension IDs to the `-128 to 127` range. `registerGroup` solves this by letting you group multiple subtypes under a single ID using internal subIds.

```dart
mp.registerGroup(
  extId: 2,
  builder: (group) {
    group.add<Address>(
      subId: 1,
      encoder: (addr, packer) => packer
        ..packString(addr.city)
        ..packString(addr.street),
      decoder: (unpacker, length) => Address(
        city: unpacker.unpackString()!,
        street: unpacker.unpackString()!,
      ),
    );
    group.add<User>(
      subId: 2,
      encoder: (user, packer) => packer
        ..packString(user.name)
        ..packArray(user.addresses), // Automatically encodes nested Address objects!
      decoder: (unpacker, length) => User(
        name: unpacker.unpackString()!,
        // Type-safe, zero-allocation array decoding
        addresses: unpacker.unpackArrayOf<Address>(),
      ),
    );
  },
);
```

### 3. Zero-Allocation Streaming (Async Data)

When reading from TCP sockets or chunks, data is often fragmented. The `streamDecoder` uses a transactional scanner to parse fragments byte-by-byte **without allocating temporary buffers**.

```dart
// 1. We simulate a highly fragmented TCP socket stream
final socket = StreamController<List<int>>();

// 2. Attach the zero-allocation MessagePack stream decoder
final messageStream = socket.stream.transform(mp.streamDecoder);

// 3. Listen for fully decoded objects seamlessly
messageStream.listen((object) {
  print('Received Object: $object');
});

// Even if you send data 1 byte at a time, streamDecoder will reconstruct it!
socket.add([0x81]); // Start map
socket.add([0xA4]); // String 'name' header
// ...
```

### 4. Big Data File Streaming (Batched Writes)

When generating huge files, re-using the underlying `BinaryWriterPool` via `Packer` batching provides massive I/O performance.

```dart
// Writing Phase
final packerStream = Packer(initialBufferSize: 65536);

for (var i = 0; i < 500000; i++) {
  packerStream.packArray([ timestamp, price, volume ]);

  // Batch writes to avoid ios.add I/O overhead (flush approx every 64k)
  if (packerStream.bytesWritten >= 64000) {
    // takeBytes(dispose: false) flushes the buffer but reuses the Packer!
    ios.add(packerStream.takeBytes(dispose: false)); 
  }
}
// Final flush
if (packerStream.bytesWritten > 0) ios.add(packerStream.takeBytes());

// Reading Phase (Incremental, O(1) Memory)
final tickStream = file.openRead().transform(mp.streamDecoder);
await for (final tick in tickStream) {
  // Process half a million records dynamically without memory spikes!
}
```

### 5. Field-by-Field Codecs (Schema / Codegen)

When the shape of a struct is known statically (e.g. a code generator emitting a codec per class), you can frame a map or array and stream its entries with the **typed** packers — without building an intermediate `Map`/`List` and without re-dispatching every value through the generic `pack()`. `Unpacker.skip()` drops unknown fields, so old readers stay compatible with newer writers.

```dart
// Encode a struct as `{ fieldId: value }` — no intermediate Map allocated.
void encode(Sensor s, Packer p) {
  p
    ..packMapLength(3)        // exactly three fields follow
    ..packInt(1)..packInt(s.id)
    ..packInt(2)..packString(s.label)
    ..packInt(3)..packBool(s.calibrated);
}

// Decode field-by-field; skip ids this version doesn't know.
Sensor decode(Unpacker u) {
  var id = 0; var label = ''; var calibrated = false;
  final fields = u.unpackMapLength();
  for (var i = 0; i < fields; i++) {
    switch (u.unpackInt()) {
      case 1: id = u.unpackInt()!;
      case 2: label = u.unpackString()!;
      case 3: calibrated = u.unpackBool()!;
      default: u.skip();      // unknown field → forward compatible
    }
  }
  return Sensor(id: id, label: label, calibrated: calibrated);
}
```

For batch protocols, `serializeAll`/`deserializeAll` (top-level) and `MessagePack.packAll`/`unpackAll` (registry-aware) concatenate multiple values into one buffer. Decode typed collections directly with `unpackArrayOf<T>()` and `unpackMapOf<K, V>()`.

## Examples

Explore the [example](example/) directory for complete, runnable architectures:

- [Basic Usage](example/basic/): Standard serialization, Maps, Lists, and reusable instances.
- [Extensions in Depth](example/extensions/): Complex polymorphic types (`BigInt`), nested groups (`User`, `Address`), and type-safe decoding (`unpackArrayOf<T>`).
- [Incremental Codecs](example/incremental/): Field-by-field struct encoding with `packMapLength`/`unpackMapLength`, forward-compatible `skip()`, and typed `unpackMapOf<K, V>`.
- [Advanced Network Streaming](example/network_streaming/): A simulated IoT Telemetry protocol handling extreme network fragmentation.
- [File Streaming (Big Data)](example/file_streaming/): Real-world massive binary data structures with custom Headers, Magic Bytes, and batch writing.

## API Overview

For complete and detailed API documentation, visit the [official pub.dev API reference](https://pub.dev/documentation/pro_mpack/latest/pro_mpack/).

| Component | Description |
| --------- | ----------- |
| **`MessagePack`** | The main codec instance. Maintains a fast `O(1)` cache of all registered extensions and serializers. |
| **`Packer`** | The low-level zero-allocation encoder. Borrows memory from `BinaryWriterPool` to write data rapidly. Includes `packMapLength`/`packArrayLength` for framing collections, and `Packer.encode`/`encodeAll` helpers. |
| **`Unpacker`** | The low-level decoder. Reads primitive structures directly, frames collections with `unpackMapLength`/`unpackArrayLength`, decodes typed collections via `unpackArrayOf<T>`/`unpackMapOf<K, V>`, and drops unknown values with `skip()`. |
| **`streamDecoder`** | A zero-allocation `StreamTransformer` that pieces together fragmented chunks of `MessagePack` data. |
| **`serialize`/`deserialize`** | Top-level global functions for one-off convenience parsing. `serializeAll`/`deserializeAll` (and `MessagePack.packAll`/`unpackAll`) handle multiple values per buffer. |

## Error Handling

`pro_mpack` uses a modern `sealed` exception hierarchy (Dart 3+), providing granular control over error handling and actionable suggestions to fix issues.

```dart
try {
  final result = deserialize(corruptedBytes);
} on MessagePackException catch (e) {
  // Use pattern matching for exhaustive error handling
  switch (e) {
    case MessagePackFormatException():
      print('Binary data is invalid: ${e.message}');
    case MessagePackUnsupportedTypeException():
      print('No encoder for type: ${e.unsupportedType}');
    case MessagePackSizeException():
      print('Data exceeds 4GB limit: ${e.message}');
    case MessagePackConfigurationException():
      print('Invalid extension setup: ${e.message}');
  }
  
  if (e.suggestion != null) print('💡 Suggestion: ${e.suggestion}');
}
```

## License

MIT License. See [LICENSE](./LICENSE) for details.

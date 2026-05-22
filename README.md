# pro_mpack

A high-performance Dart library for serializing and deserializing data using the [MessagePack](https://github.com/msgpack/msgpack/blob/master/spec.md#messagepack-specification) format.

MessagePack is an efficient binary serialization format that's smaller and faster than JSON, while maintaining similar flexibility. This library provides a modern, clean implementation of the MessagePack specification with powerful support for custom extension types.

## Features

✨ **Unified & Modern API**
- Single entry point through the `MessagePack` class
- Support for both **Declarative** (builder pattern) and **Imperative** extension registration
- Full integration with Dart's `Codec` system (`dart:convert`)

🚀 **High Performance**
- Zero-copy operations where possible
- Efficient buffer management with `BinaryWriterPool`
- Optimized encoding/decoding paths for different value ranges
- Fast UTF-8 string handling

🔧 **Flexible & Extensible**
- Easy custom extension support with recursive packing/unpacking
- Built-in `DateTime` timestamp support
- **Groups**: Organise multiple related types under a single extension ID (great for polymorphism)
- Reusable serializer/deserializer engines for low-level control

📦 **Production Ready**
- Comprehensive test coverage
- Cross-platform support (VM, Web, Native)

## Quick Start

### Basic Usage

```dart
import 'package:pro_mpack/pro_mpack.dart';

void main() {
  // Use the default instance for standard types
  final data = {
    'name': 'Alice',
    'age': 30,
    'scores': [95, 87, 92],
  };
  
  final bytes = msgpack.pack(data);
  print('Serialized to ${bytes.length} bytes');
  
  final decoded = msgpack.unpack(bytes);
  print(decoded); // {name: Alice, age: 30, ...}
}
```

## Advanced Usage: Custom Extensions

### 1. Declarative Approach (Recommended)

Perfect for configuring your application's data protocol in one place.

```dart
final mpack = MessagePack(
  extensions: (config) {
    // Register a simple type
    config.register<BigInt>(
      extId: 1,
      encoder: (val, ctx) => ctx.pack(val.toString()),
      decoder: (bytes, ctx) => BigInt.parse(ctx.unpack<String>(bytes)!),
    );

    // Register a group of related types (saves Extension IDs)
    config.registerGroup<dynamic>(
      extId: 2,
      builder: (group) {
        group.add<Address>(
          id: 1,
          encoder: (addr, ctx) => ctx.packAll([addr.street, addr.city]),
          decoder: (data, ctx) {
            final [street as String, city as String] = ctx.unpackAll(data);
            return Address(street: street, city: city);
          },
        );
      },
    );
  },
);
```

### 2. Imperative Approach

Useful for dynamic configuration or modular extensions.

```dart
final mpack = MessagePack();

mpack.register<MyType>(
  extId: 10,
  encoder: (v, ctx) => myEncoder(v),
  decoder: (d, ctx) => myDecoder(d),
);
```

### 3. Sub-registries (Groups)

The `registerGroup` feature allows you to group multiple types under a single MessagePack extension ID (from -128 to 127). This is highly efficient and helps organize complex object hierarchies.

## API Reference

### Main Class: `MessagePack`

- `pack(Object? value)` -> `Uint8List`
- `unpack<T>(Uint8List data)` -> `T?`
- `packAll(Iterable<Object?> values)` -> `Uint8List`
- `unpackAll(Uint8List data)` -> `List<Object?>`
- `register<T>({required int extId, required encoder, required decoder})`
- `registerGroup<Base>({required int extId, required builder})`

### Global Functions (for simple cases)

- `serialize(value)` - Alias for `msgpack.pack`
- `deserialize(bytes)` - Alias for `msgpack.unpack`

## Benchmarks

The library is designed for maximum throughput. Run performance tests with:

```bash
dart run test/serializer_performance_test.dart
dart run test/deserializer_performance_test.dart
```

## License

MIT License. See [LICENSE](./LICENSE) for details.

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
- **Float wrapper**: Force 32-bit float serialization with `Float`
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
  // Create a MessagePack instance
  final mpack = MessagePack();

  final data = {
    'name': 'Alice',
    'age': 30,
    'scores': [95, 87, 92],
  };

  final bytes = mpack.pack(data);
  print('Serialized to ${bytes.length} bytes');

  // Unpack and cast if needed
  final decoded = mpack.unpack<Map>(bytes);
  print(decoded); // {name: Alice, age: 30, ...}
}
```

### Simple Functions

For quick serialization without creating an instance, use the top-level functions:

```dart
import 'package:pro_mpack/pro_mpack.dart';

void main() {
  // Single value serialization/deserialization
  final bytes = serialize({'key': 'value', 'count': 42});
  final decoded = deserialize(bytes);
  print(decoded); // {key: value, count: 42}

  // Multiple values serialized to a single buffer
  final multiBytes = serializeAll([1, 'hello', true, {'nested': true}]);
  final decodedAll = deserializeAll(multiBytes);
  print(decodedAll); // [1, hello, true, {nested: true}]

  // Optional parameters
  final withBuffer = serialize({'data': 'large'}, initialBufferSize: 2048);
  final withMapOrder = deserialize(
    serialize({'z': 1, 'a': 2}),
    preserveMapOrder: true, // preserves insertion order
  );
}
```

## Advanced Usage: Custom Extensions

### 1. Declarative Approach (Recommended)

Perfect for configuring your application's data protocol in one place.

```dart
final mpack = MessagePack(
  extensions: (config) {
    // Register a custom codec for BigInt, which is not natively supported by MessagePack
    config.register<BigInt>(
      extId: 1,
      encoder: (val, ctx) => ctx.pack(val.toString()),
      decoder: (bytes, ctx) => BigInt.parse(ctx.unpack<String>(bytes)),
    );

    // Register a group of related types under a common base class
    config.registerGroup<dynamic>(
      extId: 2,
      builder: (group) {
        group.add<Address>(
          subId: 1,
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

class Address {
  const Address({required this.street, required this.city});
  final String street;
  final String city;
}
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

MessagePack extension IDs are limited to the range -128 to 127 (256 values total). When you have many related types or polymorphic hierarchies, registering each type separately quickly exhausts this space. `registerGroup` solves this by letting you group multiple subtypes under a single extension ID — each subtype uses an internal `subId` to distinguish itself.

This is ideal for:
- **Polymorphic types**: A base class with many subclasses (e.g., `Shape` → `Circle`, `Square`, `Triangle`)
- **Organized type families**: Related models that share a namespace (e.g., all `User`-related types)
- **ID conservation**: Reducing the number of extension IDs consumed when you have many small types

```dart
mpack.registerGroup<Shape>(
  extId: 20,
  builder: (group) {
    group.add<Circle>(
      subId: 1,
      encoder: (c, ctx) => ctx.pack(c.radius),
      decoder: (d, ctx) => Circle(ctx.unpack(d)),
    );
    group.add<Square>(
      subId: 2,
      encoder: (s, ctx) => ctx.pack(s.side),
      decoder: (d, ctx) => Square(ctx.unpack(d)),
    );
  },
);
```

### 4. Float Wrapper

By default, `double` values are serialized as 64-bit floats. Use the `Float` wrapper for 32-bit:

```dart
final bytes = mpack.pack(Float(3.14)); // Serialized as float32
```

## Error Handling

`pro_mpack` uses a modern `sealed` exception hierarchy (Dart 3.10+), providing granular control over error handling and actionable suggestions to fix issues.

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
  
  // Every exception includes a helpful suggestion
  if (e.suggestion != null) {
    print('💡 Suggestion: ${e.suggestion}');
  }
}
```

## Testing

The library includes comprehensive tests covering all features and edge cases. To run the tests, use:

```bash
dart test

```

## License

MIT License. See [LICENSE](./LICENSE) for details.

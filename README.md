# pro_mpack

A high-performance Dart library for serializing and deserializing data using the [MessagePack](https://github.com/msgpack/msgpack/blob/master/spec.md#messagepack-specification) format.

MessagePack is an efficient binary serialization format that's smaller and faster than JSON, while maintaining similar flexibility. This library provides a complete implementation of the MessagePack specification with support for custom extension types.

## Features

✨ **Complete MessagePack Implementation**

- Full support for all MessagePack types: nil, boolean, integer, float, string, binary, array, map, and extension
- Handles integers from 8-bit to 64-bit (signed and unsigned)
- Both 32-bit (float) and 64-bit (double) floating-point numbers

🚀 **High Performance**

- Zero-copy operations where possible
- Efficient buffer management with configurable sizes
- Optimized encoding/decoding paths for different value ranges
- Fast UTF-8 string handling

🔧 **Flexible & Extensible**

- Custom extension type support via `ExtEncoder` and `ExtDecoder` mixins
- Built-in `DateTime` timestamp encoding/decoding
- Serialize/deserialize single values or multiple consecutive values
- Reusable serializer and deserializer instances

📦 **Production Ready**

- Comprehensive test coverage
- Well-documented API with examples
- Active maintenance and updates
- Cross-platform support (VM, Web, Native)

## Installation

Add `pro_mpack` to your `pubspec.yaml` file:

```yaml
dependencies:
  pro_mpack: ^2.0.2
```

Then run `dart pub get` or `flutter pub get` to install the package.

## Quick Start

### Basic Serialization and Deserialization

```dart
import 'package:pro_mpack/pro_mpack.dart';

void main() {
  // Serialize various data types
  final data = {
    'name': 'Alice',
    'age': 30,
    'scores': [95, 87, 92],
    'metadata': {'premium': true},
  };
  
  final bytes = serialize(data);
  print('Serialized to ${bytes.length} bytes');
  
  // Deserialize back to Dart objects
  final decoded = deserialize(bytes);
  print(decoded); // {name: Alice, age: 30, scores: [95, 87, 92], ...}
}
```

### Supported Types

MessagePack/pro_mpack supports encoding these Dart types:

| Dart Type | MessagePack Type | Notes |
|-----------|-----------------|-------|
| `null` | nil | - |
| `bool` | boolean | true/false |
| `int` | integer | Automatically chooses optimal size (8/16/32/64-bit) |
| `double` | float64 | 64-bit floating point |
| `Float` | float32 | 32-bit floating point (wrap with `Float(value)`) |
| `String` | string | UTF-8 encoded |
| `Uint8List` | binary | Raw binary data |
| `ByteData` | binary | Converted to binary |
| `List` | array | Nested lists supported |
| `Map` | map | Any key/value types |
| `DateTime` | extension | Built-in timestamp extension type (-1) |
| Custom types | extension | Via `ExtEncoder`/`ExtDecoder` |

### Multiple Values

Serialize and deserialize multiple values consecutively:

```dart
// Serialize multiple values (not wrapped in an array)
final bytes = serializeAll([123, 'hello', true]);

// Deserialize all values
final values = deserializeAll(bytes);
print(values); // [123, hello, true]
```

This differs from `serialize([...])` which wraps values in a MessagePack array.

### 32-bit Floats

Save space by using 32-bit floats instead of 64-bit doubles:

```dart
final data = {
  'precise': 3.14159265359,  // Encoded as float64
  'compact': Float(3.14),     // Encoded as float32 (saves 4 bytes)
};

final bytes = serialize(data);
```

## Advanced Usage

### Custom Extension Types

Implement custom serialization for your own types using `ExtEncoder` and `ExtDecoder` mixins.

```dart
import 'dart:typed_data';

import 'package:pro_binary/pro_binary.dart';
import 'package:pro_mpack/pro_mpack.dart';

enum TimeStampFormat {
  ts32,
  ts64,
  ts96;

  static TimeStampFormat fromLength(int length) {
    switch (length) {
      case 4:
        return ts32;
      case 8:
        return ts64;
      case 12:
        return ts96;
      default:
        throw Exception('Invalid timestamp length');
    }
  }
}

/// Custom extension encoder for serializing DateTime objects.
class CustomTypesExtEncoder with ExtEncoder {
  CustomTypesExtEncoder({required this.timeStampFormat});

  /// The format of the timestamp.
  final TimeStampFormat timeStampFormat;

  @override
  int? extTypeForObject(Object? object) {
    if (object is DateTime) {
      return -1;
    }

    throw Exception('Unknown object type');
  }

  @override
  Uint8List encodeObject(Object? object) {
    if (object is DateTime) {
      final writer = BinaryWriter();

      switch (timeStampFormat) {
        case TimeStampFormat.ts32:
          final seconds = object.millisecondsSinceEpoch ~/ 1000;
          writer.writeUint32(seconds);
        case TimeStampFormat.ts64:
          final seconds = object.millisecondsSinceEpoch ~/ 1000;
          final nanoSeconds = (object.microsecondsSinceEpoch % 1000000) * 1000;
          writer.writeUint32(nanoSeconds);
          writer.writeUint32(seconds);
        case TimeStampFormat.ts96:
          final seconds = object.millisecondsSinceEpoch ~/ 1000;
          final nanoSeconds = (object.microsecondsSinceEpoch % 1000000) * 1000;
          writer.writeUint32(nanoSeconds);
          writer.writeInt64(seconds);
      }

      return writer.takeBytes();
    }

    throw Exception('Unknown object type');
  }
}

/// Custom extension decoder for deserializing DateTime objects.
class CustomTypesExtDecoder implements ExtDecoder {
  @override
  Object? decodeObject(int extType, Uint8List data) {
    if (extType == -1) {
      final type = TimeStampFormat.fromLength(data.length);
      final reader = BinaryReader(data);
      switch (type) {
        // Timestamp 32: stores the number of seconds that have elapsed since
        // 1970-01-01 00:00:00 UTC in a 32-bit unsigned integer.
        case TimeStampFormat.ts32:
          final seconds = reader.readUint32();
          return DateTime.fromMillisecondsSinceEpoch(
            seconds * 1000,
            isUtc: true,
          );
        // Timestamp 64: stores the number of seconds and nanoseconds that have
        // elapsed since 1970-01-01 00:00:00 UTC in 32-bit unsigned integers.
        case TimeStampFormat.ts64:
          final nanoSeconds = reader.readUint32();
          final seconds = reader.readUint32();
          return DateTime.fromMillisecondsSinceEpoch(
            seconds * 1000,
            isUtc: true,
          ).add(Duration(microseconds: nanoSeconds ~/ 1000));
        // Timestamp 96: stores the number of seconds and nanoseconds that have
        // elapsed since 1970-01-01 00:00:00 UTC in a 64-bit signed integer and
        // a 32-bit unsigned integer.
        case TimeStampFormat.ts96:
          final nanoSeconds = reader.readUint32();
          final seconds = reader.readInt64();
          return DateTime.fromMillisecondsSinceEpoch(
            seconds * 1000,
            isUtc: true,
          ).add(Duration(microseconds: nanoSeconds ~/ 1000));
      }
    }
    throw UnimplementedError();
  }
}

void main() {
  // Serialize with custom extension encoder
  final date = DateTime.utc(2021, 1, 1, 12, 32, 5, 880, 999);
  final userData = serialize(
    {
      'id': 1,
      'name': 'John Doe',
      'created': date,
      'updated': date.add(const Duration(days: 1)),
    },
    extEncoder: CustomTypesExtEncoder(
      timeStampFormat: TimeStampFormat.ts64,
    ),
  );

  // Deserialize with custom extension decoder
  final deserializedData = deserialize(
    userData,
    extDecoder: CustomTypesExtDecoder(),
  );

  print(deserializedData);
  // Output:
  // {
  //  id: 1,
  //  name: John Doe,
  //  created: 2021-01-01 12:32:05.880999Z,
  //  updated: 2021-01-02 12:32:05.880999Z
  //}
}
```

**Note:** `DateTime` is already supported as a built-in extension type (-1) using the MessagePack timestamp format. The example above demonstrates the custom extension mechanism.

### Reusable Serializers

For better performance when encoding multiple values, reuse a serializer instance:

```dart
final serializer = Serializer(initialBufferSize: 8192);

// Encode multiple values
serializer.encode({'message': 'first'});
final bytes1 = serializer.takeBytes();

serializer.encode({'message': 'second'});
final bytes2 = serializer.takeBytes();

// The serializer is reused, avoiding allocations
```

### Buffer Size Optimization

Choose appropriate buffer sizes based on your data:

```dart
// Small messages (default: 1024 bytes)
final smallData = serialize({'id': 123}, initialBufferSize: 512);

// Large messages
final largeData = serialize(
  bigDataStructure,
  initialBufferSize: 16384, // 16 KB
);
```

Larger initial buffers reduce reallocations but consume more memory upfront.

## Performance Considerations

### Best Practices

- **Reuse instances**: Create `Serializer` and `Deserializer` instances once and reuse them
- **Buffer sizing**: Set `initialBufferSize` appropriately to minimize reallocations
- **Type awareness**: Use `Float` when 32-bit precision is sufficient
- **Zero-copy**: `Uint8List` and `ByteData` are encoded without copying when possible

### Benchmarks

The library includes performance benchmarks. Run them with:

```bash
dart run test/serializer_performance_test.dart
dart run test/deserializer_performance_test.dart
```

## API Reference

### Top-level Functions

- `Uint8List serialize(Object? value, {ExtEncoder? extEncoder, int initialBufferSize = 1024})`
  - Serializes a single value to MessagePack
- `Uint8List serializeAll(Iterable<Object?> values, {ExtEncoder? extEncoder, int initialBufferSize = 1024})`
  - Serializes multiple values consecutively
- `Object? deserialize(Uint8List list, {ExtDecoder? extDecoder, bool copyBinaryData = false})`
  - Deserializes a single value from MessagePack
- `List<Object?> deserializeAll(Uint8List list, {ExtDecoder? extDecoder})`
  - Deserializes all consecutive values from a buffer

### Classes

- `Serializer` - Low-level serializer with `encode()` and `takeBytes()` methods
- `Deserializer` - Low-level deserializer with `decode()` and `hasBytesAvailable` property
- `Float` - Wrapper for 32-bit floating-point values
- `MessagePackError` - Exception thrown for encoding/decoding errors

### Mixins

- `ExtEncoder` - Implement to add custom type encoding
  - `int? extTypeForObject(Object? object)` - Return extension type code or null
  - `Uint8List encodeObject(Object? object)` - Encode object to bytes
- `ExtDecoder` - Implement to add custom type decoding
  - `Object? decodeObject(int extType, Uint8List data)` - Decode extension data

## Testing

Run all tests:

```bash
dart test
```

Run specific test files:

```bash
dart test test/serializer_test.dart
dart test test/deserializer_test.dart
```

Run with coverage:

```bash
dart test --coverage=coverage
dart run coverage:format_coverage --lcov --in=coverage --out=coverage.lcov --report-on=lib
```

## Examples

Check the [example](./example) directory for more comprehensive examples:

- `main.dart` - Basic usage examples
- `complex_model_example.dart` - Complex data structures and custom types

## Contributing

Contributions are welcome! Here's how you can help:

1. **Report bugs**: Open an [issue](https://github.com/pro100andrey/pro_mpack/issues) with details and reproduction steps
2. **Suggest features**: Discuss new ideas in [issues](https://github.com/pro100andrey/pro_mpack/issues)
3. **Submit PRs**: Fork the repo, make changes, and submit a [pull request](https://github.com/pro100andrey/pro_mpack/pulls)
4. **Improve docs**: Documentation improvements are always appreciated

Please ensure:

- All tests pass (`dart test`)
- Code follows the existing style
- New features include tests
- Public APIs have documentation comments

## Resources

- [MessagePack Specification](https://github.com/msgpack/msgpack/blob/master/spec.md)
- [MessagePack Official Site](https://msgpack.org/)
- [API Documentation](https://pub.dev/documentation/pro_mpack/latest/)

## License

This project is licensed under the MIT License. See the [LICENSE](./LICENSE) file for details.

## Changelog

See [CHANGELOG.md](./CHANGELOG.md) for version history and release notes.

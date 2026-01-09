import 'dart:typed_data';

import 'package:pro_mpack/pro_mpack.dart';
import 'package:test/test.dart';

void main() {
  group('MessagePackExtension.create', () {
    test('creates extension with valid parameters', () {
      final ext = MessagePackExtension.create<String>(
        typeId: 1,
        encoder: (value, reg) => Uint8List.fromList(value.codeUnits),
        decoder: (data, reg) => String.fromCharCodes(data),
      );

      expect(ext, isA<MessagePackExtension>());
      expect(ext.typeId, 1);
    });

    test('creates extension with negative typeId', () {
      final ext = MessagePackExtension.create<String>(
        typeId: -128,
        encoder: (value, reg) => Uint8List.fromList(value.codeUnits),
        decoder: (data, reg) => String.fromCharCodes(data),
      );

      expect(ext.typeId, -128);
    });

    test('creates extension with maximum typeId', () {
      final ext = MessagePackExtension.create<String>(
        typeId: 127,
        encoder: (value, reg) => Uint8List.fromList(value.codeUnits),
        decoder: (data, reg) => String.fromCharCodes(data),
      );

      expect(ext.typeId, 127);
    });

    test('encoder receives correct value and registry', () {
      var encoderCalled = false;
      _TestClass? receivedValue;
      MessagePackRegistry? receivedRegistry;

      final registry = MessagePackRegistry();
      final ext = MessagePackExtension.create<_TestClass>(
        typeId: 1,
        encoder: (value, reg) {
          encoderCalled = true;
          receivedValue = value;
          receivedRegistry = reg;
          return Uint8List.fromList([value.id]);
        },
        decoder: (data, reg) => _TestClass(data[0]),
      );

      registry.register(ext);
      final testObj = _TestClass(42);
      registry.pack(testObj);

      expect(encoderCalled, isTrue);
      expect(receivedValue, same(testObj));
      expect(receivedRegistry, same(registry));
    });

    test('decoder receives correct data and registry', () {
      var decoderCalled = false;
      Uint8List? receivedData;
      MessagePackRegistry? receivedRegistry;

      final registry = MessagePackRegistry();
      final ext = MessagePackExtension.create<_TestClass>(
        typeId: 1,
        encoder: (value, reg) => Uint8List.fromList([value.id]),
        decoder: (data, reg) {
          decoderCalled = true;
          receivedData = data;
          receivedRegistry = reg;
          return _TestClass(data[0]);
        },
      );

      registry.register(ext);
      final packed = registry.pack(_TestClass(42));
      registry.unpack(packed);

      expect(decoderCalled, isTrue);
      expect(receivedData, isNotNull);
      expect(receivedRegistry, same(registry));
    });
  });

  group('MessagePackExtension.canHandle', () {
    test('returns true for correct type', () {
      final ext = MessagePackExtension.create<String>(
        typeId: 1,
        encoder: (value, reg) => Uint8List.fromList(value.codeUnits),
        decoder: (data, reg) => String.fromCharCodes(data),
      );

      expect(ext.canHandle('hello'), isTrue);
      expect(ext.canHandle(''), isTrue);
    });

    test('returns false for incorrect type', () {
      final ext = MessagePackExtension.create<String>(
        typeId: 1,
        encoder: (value, reg) => Uint8List.fromList(value.codeUnits),
        decoder: (data, reg) => String.fromCharCodes(data),
      );

      expect(ext.canHandle(42), isFalse);
      expect(ext.canHandle(null), isFalse);
      expect(ext.canHandle([1, 2, 3]), isFalse);
      expect(ext.canHandle({'key': 'value'}), isFalse);
    });

    test('works with nullable types', () {
      final ext = MessagePackExtension.create<String?>(
        typeId: 1,
        encoder: (value, reg) =>
            value == null ? Uint8List(0) : Uint8List.fromList(value.codeUnits),
        decoder: (data, reg) =>
            data.isEmpty ? null : String.fromCharCodes(data),
      );

      expect(ext.canHandle('hello'), isTrue);
      expect(ext.canHandle(null), isTrue);
      expect(ext.canHandle(42), isFalse);
    });

    test('works with custom classes', () {
      final ext = MessagePackExtension.create<_TestClass>(
        typeId: 1,
        encoder: (value, reg) => Uint8List.fromList([value.id]),
        decoder: (data, reg) => _TestClass(data[0]),
      );

      expect(ext.canHandle(_TestClass(1)), isTrue);
      expect(ext.canHandle(_TestClass(999)), isTrue);
      expect(ext.canHandle('string'), isFalse);
      expect(ext.canHandle(42), isFalse);
    });

    test('respects type hierarchy', () {
      final ext = MessagePackExtension.create<_TestBase>(
        typeId: 1,
        encoder: (value, reg) => Uint8List(0),
        decoder: (data, reg) => _TestDerived(0),
      );

      expect(ext.canHandle(_TestBase()), isTrue);
      expect(ext.canHandle(_TestDerived(1)), isTrue); // Derived is also Base
      expect(ext.canHandle('string'), isFalse);
    });
  });

  group('MessagePackExtension.encode', () {
    test('encodes simple type', () {
      final ext = MessagePackExtension.create<String>(
        typeId: 1,
        encoder: (value, reg) => Uint8List.fromList(value.codeUnits),
        decoder: (data, reg) => String.fromCharCodes(data),
      );

      final registry = MessagePackRegistry();
      final result = ext.encode('hello', registry);

      expect(result, Uint8List.fromList('hello'.codeUnits));
    });

    test('encodes custom class', () {
      final ext = MessagePackExtension.create<_TestClass>(
        typeId: 1,
        encoder: (value, reg) => Uint8List.fromList([value.id]),
        decoder: (data, reg) => _TestClass(data[0]),
      );

      final registry = MessagePackRegistry();
      final result = ext.encode(_TestClass(42), registry);

      expect(result, Uint8List.fromList([42]));
    });

    test('can use registry in encoder', () {
      final registry = MessagePackRegistry();

      final ext = MessagePackExtension.create<_TestNestedClass>(
        typeId: 1,
        encoder: (value, reg) {
          // Use registry to pack nested data
          final innerPacked = reg.packAll([value.name, value.value]);
          return innerPacked;
        },
        decoder: (data, reg) {
          final values = reg.unpackAll(data);
          return _TestNestedClass(values[0]! as String, values[1]! as int);
        },
      );

      registry.register(ext);
      final obj = _TestNestedClass('test', 123);
      final result = ext.encode(obj, registry);

      expect(result, isA<Uint8List>());
      expect(result.isNotEmpty, isTrue);
    });

    test('handles empty data', () {
      final ext = MessagePackExtension.create<String>(
        typeId: 1,
        encoder: (value, reg) => Uint8List(0),
        decoder: (data, reg) => '',
      );

      final registry = MessagePackRegistry();
      final result = ext.encode('', registry);

      expect(result, Uint8List(0));
    });

    test('handles large data', () {
      final ext = MessagePackExtension.create<String>(
        typeId: 1,
        encoder: (value, reg) => Uint8List.fromList(value.codeUnits),
        decoder: (data, reg) => String.fromCharCodes(data),
      );

      final registry = MessagePackRegistry();
      final longString = 'a' * 10000;
      final result = ext.encode(longString, registry);

      expect(result.length, 10000);
    });
  });

  group('MessagePackExtension.decode', () {
    test('decodes simple type', () {
      final ext = MessagePackExtension.create<String>(
        typeId: 1,
        encoder: (value, reg) => Uint8List.fromList(value.codeUnits),
        decoder: (data, reg) => String.fromCharCodes(data),
      );

      final registry = MessagePackRegistry();
      final data = Uint8List.fromList('hello'.codeUnits);
      final result = ext.decode(data, registry);

      expect(result, 'hello');
    });

    test('decodes custom class', () {
      final ext = MessagePackExtension.create<_TestClass>(
        typeId: 1,
        encoder: (value, reg) => Uint8List.fromList([value.id]),
        decoder: (data, reg) => _TestClass(data[0]),
      );

      final registry = MessagePackRegistry();
      final data = Uint8List.fromList([42]);
      final result = ext.decode(data, registry)! as _TestClass;

      expect(result.id, 42);
    });

    test('can use registry in decoder', () {
      final registry = MessagePackRegistry();

      final ext = MessagePackExtension.create<_TestNestedClass>(
        typeId: 1,
        encoder: (value, reg) => reg.packAll([value.name, value.value]),
        decoder: (data, reg) {
          final values = reg.unpackAll(data);
          return _TestNestedClass(values[0]! as String, values[1]! as int);
        },
      );

      registry.register(ext);
      final encoded = ext.encode(_TestNestedClass('test', 123), registry);
      final result = ext.decode(encoded, registry)! as _TestNestedClass;

      expect(result.name, 'test');
      expect(result.value, 123);
    });

    test('handles empty data', () {
      final ext = MessagePackExtension.create<String>(
        typeId: 1,
        encoder: (value, reg) => Uint8List(0),
        decoder: (data, reg) => data.isEmpty ? 'empty' : 'not empty',
      );

      final registry = MessagePackRegistry();
      final result = ext.decode(Uint8List(0), registry);

      expect(result, 'empty');
    });

    test('handles large data', () {
      final ext = MessagePackExtension.create<String>(
        typeId: 1,
        encoder: (value, reg) => Uint8List.fromList(value.codeUnits),
        decoder: (data, reg) => String.fromCharCodes(data),
      );

      final registry = MessagePackRegistry();
      final longData = Uint8List.fromList(
        List.filled(10000, 97),
      ); // 'a' * 10000
      final result = ext.decode(longData, registry);

      expect(result, 'a' * 10000);
    });
  });

  group('MessagePackExtension round-trip', () {
    test('round-trips String', () {
      final ext = MessagePackExtension.create<String>(
        typeId: 1,
        encoder: (value, reg) => Uint8List.fromList(value.codeUnits),
        decoder: (data, reg) => String.fromCharCodes(data),
      );

      final registry = MessagePackRegistry()..register(ext);

      const original = 'Hello, World!';
      final packed = registry.pack(original);
      final unpacked = registry.unpack<String>(packed);

      expect(unpacked, original);
    });

    test('round-trips DateTime', () {
      final ext = MessagePackExtension.create<DateTime>(
        typeId: 1,
        encoder: (dt, reg) =>
            Uint8List.fromList(dt.toIso8601String().codeUnits),
        decoder: (data, reg) => DateTime.parse(String.fromCharCodes(data)),
      );

      final registry = MessagePackRegistry()..register(ext);

      final original = DateTime.utc(2024, 1, 15, 10, 30, 45);
      final packed = registry.pack(original);
      final unpacked = registry.unpack<DateTime>(packed);

      expect(unpacked, original);
    });

    test('round-trips custom class', () {
      final ext = MessagePackExtension.create<_TestClass>(
        typeId: 1,
        encoder: (value, reg) => Uint8List.fromList([value.id]),
        decoder: (data, reg) => _TestClass(data[0]),
      );

      final registry = MessagePackRegistry()..register(ext);

      final original = _TestClass(42);
      final packed = registry.pack(original);
      final unpacked = registry.unpack<_TestClass>(packed)!;

      expect(unpacked.id, original.id);
    });

    test('round-trips complex nested class', () {
      final ext = MessagePackExtension.create<_TestNestedClass>(
        typeId: 1,
        encoder: (value, reg) => reg.packAll([value.name, value.value]),
        decoder: (data, reg) {
          final values = reg.unpackAll(data);
          return _TestNestedClass(values[0]! as String, values[1]! as int);
        },
      );

      final registry = MessagePackRegistry()..register(ext);

      final original = _TestNestedClass('test', 999);
      final packed = registry.pack(original);
      final unpacked = registry.unpack<_TestNestedClass>(packed)!;

      expect(unpacked.name, original.name);
      expect(unpacked.value, original.value);
    });

    test('round-trips list of custom objects', () {
      final ext = MessagePackExtension.create<_TestClass>(
        typeId: 1,
        encoder: (value, reg) => Uint8List.fromList([value.id]),
        decoder: (data, reg) => _TestClass(data[0]),
      );

      final registry = MessagePackRegistry()..register(ext);

      final original = [_TestClass(1), _TestClass(2), _TestClass(3)];
      final packed = registry.packAll(original);
      final unpacked = registry.unpackAll(packed);

      expect(unpacked.length, 3);
      expect((unpacked[0]! as _TestClass).id, 1);
      expect((unpacked[1]! as _TestClass).id, 2);
      expect((unpacked[2]! as _TestClass).id, 3);
    });
  });

  group('MessagePackExtension with different types', () {
    test('works with int type', () {
      final ext = MessagePackExtension.create<int>(
        typeId: 1,
        encoder: (value, reg) => Uint8List.fromList([value & 0xFF]),
        decoder: (data, reg) => data[0],
      );

      expect(ext.canHandle(42), isTrue);
      expect(ext.canHandle('42'), isFalse);
    });

    test('works with double type', () {
      final ext = MessagePackExtension.create<double>(
        typeId: 1,
        encoder: (value, reg) =>
            Uint8List(8)..buffer.asByteData().setFloat64(0, value),
        decoder: (data, reg) => data.buffer.asByteData().getFloat64(0),
      );

      expect(ext.canHandle(3.14), isTrue);
      expect(ext.canHandle(42), isFalse);
    });

    test('works with bool type', () {
      final ext = MessagePackExtension.create<bool>(
        typeId: 1,
        encoder: (value, reg) => Uint8List.fromList([if (value) 1 else 0]),
        decoder: (data, reg) => data[0] == 1,
      );

      expect(ext.canHandle(true), isTrue);
      expect(ext.canHandle(false), isTrue);
      expect(ext.canHandle(1), isFalse);
    });

    test('works with List type', () {
      final ext = MessagePackExtension.create<List<int>>(
        typeId: 1,
        encoder: (value, reg) => Uint8List.fromList(value),
        decoder: (data, reg) => data.toList(),
      );

      expect(ext.canHandle([1, 2, 3]), isTrue);
      expect(ext.canHandle('string'), isFalse);
    });

    test('works with Map type', () {
      final ext = MessagePackExtension.create<Map<String, int>>(
        typeId: 1,
        encoder: (value, reg) => reg.pack(value),
        decoder: (data, reg) => reg.unpack<Map>(data)!.cast<String, int>(),
      );

      expect(ext.canHandle({'a': 1}), isTrue);
      expect(ext.canHandle([1, 2]), isFalse);
    });

    test('works with Uri type', () {
      final ext = MessagePackExtension.create<Uri>(
        typeId: 1,
        encoder: (uri, reg) => Uint8List.fromList(uri.toString().codeUnits),
        decoder: (data, reg) => Uri.parse(String.fromCharCodes(data)),
      );

      final registry = MessagePackRegistry()..register(ext);

      final uri = Uri.parse('https://example.com');
      final packed = registry.pack(uri);
      final unpacked = registry.unpack<Uri>(packed);

      expect(unpacked.toString(), uri.toString());
    });
  });

  group('MessagePackExtension edge cases', () {
    test('handles null in nullable type', () {
      final ext = MessagePackExtension.create<String?>(
        typeId: 1,
        encoder: (value, reg) =>
            value == null ? Uint8List(0) : Uint8List.fromList(value.codeUnits),
        decoder: (data, reg) =>
            data.isEmpty ? null : String.fromCharCodes(data),
      );

      final registry = MessagePackRegistry()..register(ext);

      final packed = registry.pack(null);
      final unpacked = registry.unpack<String?>(packed);

      expect(unpacked, isNull);
    });

    test('handles unicode strings', () {
      final ext = MessagePackExtension.create<String>(
        typeId: 1,
        encoder: (value, reg) => Uint8List.fromList(value.codeUnits),
        decoder: (data, reg) => String.fromCharCodes(data),
      );

      final registry = MessagePackRegistry()..register(ext);

      const original = '你好世界 🌍 مرحبا';
      final packed = registry.pack(original);
      final unpacked = registry.unpack<String>(packed);

      expect(unpacked, original);
    });

    test('handles empty string', () {
      final ext = MessagePackExtension.create<String>(
        typeId: 1,
        encoder: (value, reg) => Uint8List.fromList(value.codeUnits),
        decoder: (data, reg) => String.fromCharCodes(data),
      );

      final registry = MessagePackRegistry()..register(ext);

      final packed = registry.pack('');
      final unpacked = registry.unpack<String>(packed);

      expect(unpacked, '');
    });

    test('handles maximum typeId value', () {
      final ext = MessagePackExtension.create<String>(
        typeId: 127,
        encoder: (value, reg) => Uint8List.fromList(value.codeUnits),
        decoder: (data, reg) => String.fromCharCodes(data),
      );

      final registry = MessagePackRegistry()..register(ext);

      final packed = registry.pack('test');
      final unpacked = registry.unpack<String>(packed);

      expect(unpacked, 'test');
    });

    test('handles minimum typeId value', () {
      final ext = MessagePackExtension.create<String>(
        typeId: -128,
        encoder: (value, reg) => Uint8List.fromList(value.codeUnits),
        decoder: (data, reg) => String.fromCharCodes(data),
      );

      final registry = MessagePackRegistry()..register(ext);

      final packed = registry.pack('test');
      final unpacked = registry.unpack<String>(packed);

      expect(unpacked, 'test');
    });
  });

  group('MessagePackExtension with registry nesting', () {
    test('encoder can use registry for nested objects', () {
      final registry = MessagePackRegistry();

      // Register inner type
      final innerExt = MessagePackExtension.create<_TestInner>(
        typeId: 1,
        encoder: (value, reg) => Uint8List.fromList([value.data]),
        decoder: (data, reg) => _TestInner(data[0]),
      );
      registry.register(innerExt);

      // Register outer type that uses inner
      final outerExt = MessagePackExtension.create<_TestOuter>(
        typeId: 2,
        encoder: (value, reg) {
          final innerPacked = reg.pack(value.inner);
          final result = Uint8List(innerPacked.length + 1);
          result[0] = value.id;
          result.setRange(1, result.length, innerPacked);
          return result;
        },
        decoder: (data, reg) {
          final id = data[0];
          final innerData = Uint8List.sublistView(data, 1);
          final inner = reg.unpack<_TestInner>(innerData)!;
          return _TestOuter(id, inner);
        },
      );
      registry.register(outerExt);

      final original = _TestOuter(99, _TestInner(42));
      final packed = registry.pack(original);
      final unpacked = registry.unpack<_TestOuter>(packed)!;

      expect(unpacked.id, 99);
      expect(unpacked.inner.data, 42);
    });

    test('decoder can use registry for nested objects', () {
      final registry = MessagePackRegistry();

      final ext1 = MessagePackExtension.create<_TestNestedClass>(
        typeId: 1,
        encoder: (value, reg) => reg.packAll([value.name, value.value]),
        decoder: (data, reg) {
          final unpacked = reg.unpackAll(data);
          return _TestNestedClass(
            unpacked[0]! as String,
            unpacked[1]! as int,
          );
        },
      );

      registry.register(ext1);

      final original = _TestNestedClass('nested', 777);
      final packed = registry.pack(original);
      final unpacked = registry.unpack<_TestNestedClass>(packed)!;

      expect(unpacked.name, 'nested');
      expect(unpacked.value, 777);
    });
  });
}

// Test helper classes
class _TestClass {
  _TestClass(this.id);
  final int id;
}

class _TestBase {
  _TestBase();
}

class _TestDerived extends _TestBase {
  _TestDerived(this.value);
  final int value;
}

class _TestNestedClass {
  _TestNestedClass(this.name, this.value);
  final String name;
  final int value;
}

class _TestInner {
  _TestInner(this.data);
  final int data;
}

class _TestOuter {
  _TestOuter(this.id, this.inner);
  final int id;
  final _TestInner inner;
}

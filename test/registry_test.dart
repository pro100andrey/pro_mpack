import 'dart:typed_data';

import 'package:pro_mpack/pro_mpack.dart';
import 'package:test/test.dart';

void main() {
  group('MessagePackRegistry', () {
    test('creates empty registry', () {
      final registry = MessagePackRegistry();
      expect(registry, isA<MessagePackRegistry>());
    });

    test('creates registry with initial extensions', () {
      final ext1 = MessagePackExtension.create<String>(
        typeId: 1,
        encoder: (value, reg) => Uint8List.fromList(value.codeUnits),
        decoder: (data, reg) => String.fromCharCodes(data),
      );
      final ext2 = MessagePackExtension.create<int>(
        typeId: 2,
        encoder: (value, reg) => Uint8List.fromList([value]),
        decoder: (data, reg) => data[0],
      );

      final registry = MessagePackRegistry([ext1, ext2]);
      expect(registry, isA<MessagePackRegistry>());
    });
  });

  group('MessagePackRegistry.register', () {
    test('registers single extension', () {
      final registry = MessagePackRegistry();
      final ext = MessagePackExtension.create<DateTime>(
        typeId: 1,
        encoder: (dt, reg) => Uint8List.fromList(
          dt.toIso8601String().codeUnits,
        ),
        decoder: (data, reg) => DateTime.parse(
          String.fromCharCodes(data),
        ),
      );

      final result = registry.register(ext);
      expect(result, same(registry)); // Method chaining
    });

    test('throws when registering duplicate typeId', () {
      final registry = MessagePackRegistry();
      final ext1 = MessagePackExtension.create<String>(
        typeId: 1,
        encoder: (value, reg) => Uint8List.fromList(value.codeUnits),
        decoder: (data, reg) => String.fromCharCodes(data),
      );
      final ext2 = MessagePackExtension.create<int>(
        typeId: 1, // Same typeId
        encoder: (value, reg) => Uint8List.fromList([value]),
        decoder: (data, reg) => data[0],
      );

      registry.register(ext1);
      expect(
        () => registry.register(ext2),
        throwsA(isA<Exception>()),
      );
    });

    test('allows method chaining', () {
      final registry = MessagePackRegistry();
      final ext1 = MessagePackExtension.create<String>(
        typeId: 1,
        encoder: (value, reg) => Uint8List.fromList(value.codeUnits),
        decoder: (data, reg) => String.fromCharCodes(data),
      );
      final ext2 = MessagePackExtension.create<int>(
        typeId: 2,
        encoder: (value, reg) => Uint8List.fromList([value]),
        decoder: (data, reg) => data[0],
      );

      final result = registry.register(ext1).register(ext2);
      expect(result, same(registry));
    });
  });

  group('MessagePackRegistry.pack and unpack', () {
    test('packs and unpacks DateTime', () {
      final registry = MessagePackRegistry();
      final ext = MessagePackExtension.create<DateTime>(
        typeId: 1,
        encoder: (dt, reg) => Uint8List.fromList(
          dt.toIso8601String().codeUnits,
        ),
        decoder: (data, reg) => DateTime.parse(
          String.fromCharCodes(data),
        ),
      );
      registry.register(ext);

      final now = DateTime.utc(2024, 1, 15, 12, 30, 45);
      final packed = registry.pack(now);
      final unpacked = registry.unpack<DateTime>(packed);

      expect(unpacked, now);
    });

    test('packs and unpacks custom class', () {
      final registry = MessagePackRegistry();

      final ext = MessagePackExtension.create<_TestPerson>(
        typeId: 10,
        encoder: (person, reg) => reg.packAll([person.name, person.age]),
        decoder: (data, reg) {
          final values = reg.unpackAll(data);
          return _TestPerson(values[0]! as String, values[1]! as int);
        },
      );
      registry.register(ext);

      final person = _TestPerson('Alice', 30);
      final packed = registry.pack(person);
      final unpacked = registry.unpack<_TestPerson>(packed);

      expect(unpacked.name, person.name);
      expect(unpacked.age, person.age);
    });

    test('packs and unpacks null', () {
      final registry = MessagePackRegistry();
      final packed = registry.pack(null);
      final unpacked = registry.unpack<Object?>(packed);

      expect(unpacked, isNull);
    });

    test('packs and unpacks standard types', () {
      final registry = MessagePackRegistry();

      expect(registry.unpack<int>(registry.pack(42)), 42);
      expect(registry.unpack<String>(registry.pack('hello')), 'hello');
      expect(registry.unpack<bool>(registry.pack(true)), true);
      expect(registry.unpack<List<dynamic>>(registry.pack([1, 2, 3])), [
        1,
        2,
        3,
      ]);
    });
  });

  group('MessagePackRegistry.packAll and unpackAll', () {
    test('packs and unpacks multiple values', () {
      final registry = MessagePackRegistry();
      final values = [1, 'hello', true, null, 3.14];

      final packed = registry.packAll(values);
      final unpacked = registry.unpackAll(packed);

      expect(unpacked[0], 1);
      expect(unpacked[1], 'hello');
      expect(unpacked[2], true);
      expect(unpacked[3], null);
      expect(unpacked[4], closeTo(3.14, 0.001));
    });

    test('packs and unpacks empty list', () {
      final registry = MessagePackRegistry();
      final values = <Object?>[];

      final packed = registry.packAll(values);
      final unpacked = registry.unpackAll(packed);

      expect(unpacked, isEmpty);
    });

    test('packs and unpacks custom objects in list', () {
      final registry = MessagePackRegistry();
      final ext = MessagePackExtension.create<_TestPerson>(
        typeId: 10,
        encoder: (person, reg) => reg.packAll([person.name, person.age]),
        decoder: (data, reg) {
          final values = reg.unpackAll(data);
          return _TestPerson(values[0]! as String, values[1]! as int);
        },
      );
      registry.register(ext);

      final values = [
        _TestPerson('Alice', 30),
        _TestPerson('Bob', 25),
      ];

      final packed = registry.packAll(values);
      final unpacked = registry.unpackAll(packed);

      expect(unpacked.length, 2);
      expect((unpacked[0]! as _TestPerson).name, 'Alice');
      expect((unpacked[1]! as _TestPerson).name, 'Bob');
    });
  });

  group('MessagePackRegistry.extTypeForObject', () {
    test('returns typeId for registered type', () {
      final registry = MessagePackRegistry();
      final ext = MessagePackExtension.create<DateTime>(
        typeId: 5,
        encoder: (dt, reg) => Uint8List.fromList(
          dt.toIso8601String().codeUnits,
        ),
        decoder: (data, reg) => DateTime.parse(
          String.fromCharCodes(data),
        ),
      );
      registry.register(ext);

      final typeId = registry.extTypeForObject(DateTime.now());
      expect(typeId, 5);
    });

    test('returns null for unregistered type', () {
      final registry = MessagePackRegistry();
      final typeId = registry.extTypeForObject(DateTime.now());
      expect(typeId, isNull);
    });

    test('returns null for null object', () {
      final registry = MessagePackRegistry();
      final typeId = registry.extTypeForObject(null);
      expect(typeId, isNull);
    });

    test('uses cache for subsequent lookups', () {
      final registry = MessagePackRegistry();
      final ext = MessagePackExtension.create<DateTime>(
        typeId: 5,
        encoder: (dt, reg) => Uint8List.fromList(
          dt.toIso8601String().codeUnits,
        ),
        decoder: (data, reg) => DateTime.parse(
          String.fromCharCodes(data),
        ),
      );
      registry.register(ext);

      // First lookup - should cache
      final typeId1 = registry.extTypeForObject(DateTime.now());
      // Second lookup - should use cache
      final typeId2 = registry.extTypeForObject(DateTime.now());

      expect(typeId1, typeId2);
      expect(typeId1, 5);
    });

    test('caches negative results', () {
      final registry = MessagePackRegistry();

      // First lookup
      final typeId1 = registry.extTypeForObject(DateTime.now());
      // Second lookup - should use cache
      final typeId2 = registry.extTypeForObject(DateTime.now());

      expect(typeId1, isNull);
      expect(typeId2, isNull);
    });
  });

  group('MessagePackRegistry.encodeObject', () {
    test('encodes object with registered extension', () {
      final registry = MessagePackRegistry();
      final ext = MessagePackExtension.create<_TestPerson>(
        typeId: 10,
        encoder: (person, reg) => Uint8List.fromList(
          [...person.name.codeUnits, person.age],
        ),
        decoder: (data, reg) => _TestPerson('', 0),
      );
      registry.register(ext);

      final person = _TestPerson('Alice', 30);
      final encoded = registry.encodeObject(person);

      expect(encoded, isA<Uint8List>());
      expect(encoded.isNotEmpty, isTrue);
    });

    test('throws for unregistered type', () {
      final registry = MessagePackRegistry();
      expect(
        () => registry.encodeObject(DateTime.now()),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('MessagePackRegistry.decodeObject', () {
    test('decodes object with registered extension', () {
      final registry = MessagePackRegistry();
      final ext = MessagePackExtension.create<String>(
        typeId: 10,
        encoder: (value, reg) => Uint8List.fromList(value.codeUnits),
        decoder: (data, reg) => String.fromCharCodes(data),
      );
      registry.register(ext);

      final data = Uint8List.fromList('test'.codeUnits);
      final decoded = registry.decodeObject(10, data);

      expect(decoded, 'test');
    });

    test('throws for unknown extension type', () {
      final registry = MessagePackRegistry();
      final data = Uint8List.fromList([1, 2, 3]);

      expect(
        () => registry.decodeObject(99, data),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('MessagePackRegistry nested encoding', () {
    test('encodes nested custom types', () {
      final registry = MessagePackRegistry();

      // Register Address extension
      final addressExt = MessagePackExtension.create<_TestAddress>(
        typeId: 1,
        encoder: (addr, reg) => reg.packAll([addr.street, addr.city]),
        decoder: (data, reg) {
          final values = reg.unpackAll(data);
          return _TestAddress(values[0]! as String, values[1]! as String);
        },
      );

      // Register Person extension that uses Address
      final personExt = MessagePackExtension.create<_TestPersonWithAddress>(
        typeId: 2,
        encoder: (person, reg) => reg.packAll([person.name, person.address]),
        decoder: (data, reg) {
          final values = reg.unpackAll(data);
          return _TestPersonWithAddress(
            values[0]! as String,
            values[1]! as _TestAddress,
          );
        },
      );

      registry.register(addressExt).register(personExt);

      final person = _TestPersonWithAddress(
        'Alice',
        _TestAddress('Main St', 'NYC'),
      );

      final packed = registry.pack(person);
      final unpacked = registry.unpack<_TestPersonWithAddress>(packed);

      expect(unpacked.name, 'Alice');
      expect(unpacked.address.street, 'Main St');
      expect(unpacked.address.city, 'NYC');
    });
  });

  group('MessagePackSubRegistry', () {
    test('creates empty sub-registry', () {
      final subRegistry = MessagePackSubRegistry();
      expect(subRegistry, isA<MessagePackSubRegistry>());
    });

    test('adds subtype to registry', () {
      final subRegistry = MessagePackSubRegistry();
      final result = subRegistry.add<_TestDerived1>(
        subId: 1,
        encoder: (value, reg) => Uint8List.fromList([value.value]),
        decoder: (data, reg) => _TestDerived1(data[0]),
      );

      expect(result, same(subRegistry)); // Method chaining
    });

    test('throws for negative subId', () {
      final subRegistry = MessagePackSubRegistry();
      expect(
        () => subRegistry.add<_TestDerived1>(
          subId: -1,
          encoder: (value, reg) => Uint8List.fromList([value.value]),
          decoder: (data, reg) => _TestDerived1(data[0]),
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('allows method chaining', () {
      final subRegistry = MessagePackSubRegistry();
      final result = subRegistry
          .add<_TestDerived1>(
            subId: 1,
            encoder: (value, reg) => Uint8List.fromList([value.value]),
            decoder: (data, reg) => _TestDerived1(data[0]),
          )
          .add<_TestDerived2>(
            subId: 2,
            encoder: (value, reg) => Uint8List.fromList([value.data]),
            decoder: (data, reg) => _TestDerived2(data[0]),
          );

      expect(result, same(subRegistry));
    });
  });

  group('MessagePackRegistry.registerSub', () {
    test('registers sub-registry', () {
      final registry = MessagePackRegistry();
      final subRegistry = MessagePackSubRegistry()
          .add<_TestDerived1>(
            subId: 1,
            encoder: (value, reg) => Uint8List.fromList([value.value]),
            decoder: (data, reg) => _TestDerived1(data[0]),
          )
          .add<_TestDerived2>(
            subId: 2,
            encoder: (value, reg) => Uint8List.fromList([value.data]),
            decoder: (data, reg) => _TestDerived2(data[0]),
          );

      final result = registry.registerSub(100, subRegistry);
      expect(result, same(registry)); // Method chaining
    });

    test('packs and unpacks derived type 1', () {
      final registry = MessagePackRegistry();
      final subRegistry = MessagePackSubRegistry()
          .add<_TestDerived1>(
            subId: 1,
            encoder: (value, reg) => Uint8List.fromList([value.value]),
            decoder: (data, reg) => _TestDerived1(data[0]),
          )
          .add<_TestDerived2>(
            subId: 2,
            encoder: (value, reg) => Uint8List.fromList([value.data]),
            decoder: (data, reg) => _TestDerived2(data[0]),
          );

      registry.registerSub(100, subRegistry);

      final obj = _TestDerived1(42);
      final packed = registry.pack<_TestBase>(obj);
      final unpacked = registry.unpack<_TestBase>(packed) as _TestDerived1;

      expect(unpacked.value, 42);
    });

    test('packs and unpacks derived type 2', () {
      final registry = MessagePackRegistry();
      final subRegistry = MessagePackSubRegistry()
          .add<_TestDerived1>(
            subId: 1,
            encoder: (value, reg) => Uint8List.fromList([value.value]),
            decoder: (data, reg) => _TestDerived1(data[0]),
          )
          .add<_TestDerived2>(
            subId: 2,
            encoder: (value, reg) => Uint8List.fromList([value.data]),
            decoder: (data, reg) => _TestDerived2(data[0]),
          );

      registry.registerSub(100, subRegistry);

      final obj = _TestDerived2(99);
      final packed = registry.pack<_TestBase>(obj);
      final unpacked = registry.unpack<_TestBase>(packed) as _TestDerived2;

      expect(unpacked.data, 99);
    });

    test('handles small subId optimization', () {
      final registry = MessagePackRegistry();
      final subRegistry = MessagePackSubRegistry()
          .add<_TestDerived1>(
            subId: 50, // < 128, should use single byte optimization
            encoder: (value, reg) => Uint8List.fromList([value.value]),
            decoder: (data, reg) => _TestDerived1(data[0]),
          );

      registry.registerSub(100, subRegistry);

      final obj = _TestDerived1(42);
      final packed = registry.pack<_TestBase>(obj);
      final unpacked = registry.unpack<_TestBase>(packed) as _TestDerived1;

      expect(unpacked.value, 42);
    });

    test('handles large subId with varInt encoding', () {
      final registry = MessagePackRegistry();
      final subRegistry = MessagePackSubRegistry()
          .add<_TestDerived1>(
            subId: 200, // >= 128, should use varInt
            encoder: (value, reg) => Uint8List.fromList([value.value]),
            decoder: (data, reg) => _TestDerived1(data[0]),
          );

      registry.registerSub(100, subRegistry);

      final obj = _TestDerived1(42);
      final packed = registry.pack(obj);
      final unpacked = registry.unpack< _TestDerived1>(packed);

      expect(unpacked.value, 42);
    });

    test('throws for unregistered subtype', () {
      final registry = MessagePackRegistry();
      final subRegistry = MessagePackSubRegistry()
          .add(
            subId: 1,
            encoder: (value, reg) => Uint8List.fromList([value.value]),
            decoder: (data, reg) => _TestDerived1(data[0]),
          );

      registry.registerSub(100, subRegistry);

      // Try to pack _TestDerived2 which is not registered
      final obj = _TestDerived2(42);
      expect(
        () => registry.pack<_TestBase>(obj),
        throwsA(isA<Exception>()),
      );
    });

    test('throws for unknown subTypeId during decode', () {
      final registry = MessagePackRegistry();
      final subRegistry = MessagePackSubRegistry()
          .add(
            subId: 1,
            encoder: (value, reg) => Uint8List.fromList([value.value]),
            decoder: (data, reg) => _TestDerived1(data[0]),
          );

      registry.registerSub(100, subRegistry);

      // Manually create data with unknown subId
      final ext = MessagePackExtension.create<_TestFakeType>(
        typeId: 100,
        encoder: (value, reg) => Uint8List.fromList([99, 42]),
        decoder: (data, reg) => _TestFakeType(),
      );

      final fakeRegistry = MessagePackRegistry([ext]);
      final packed = fakeRegistry.pack(_TestFakeType());

      expect(
        () => registry.unpack< _TestFakeType>(packed),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('MessagePackSubRegistry complex scenarios', () {
    test('encodes and decodes multiple subtypes in list', () {
      final registry = MessagePackRegistry();
      final subRegistry = MessagePackSubRegistry()
          .add<_TestDerived1>(
            subId: 1,
            encoder: (value, reg) => Uint8List.fromList([value.value]),
            decoder: (data, reg) => _TestDerived1(data[0]),
          )
          .add<_TestDerived2>(
            subId: 2,
            encoder: (value, reg) => Uint8List.fromList([value.data]),
            decoder: (data, reg) => _TestDerived2(data[0]),
          );

      registry.registerSub(100, subRegistry);

      final objects = <_TestBase>[
        _TestDerived1(10),
        _TestDerived2(20),
        _TestDerived1(30),
      ];

      final packed = registry.packAll(objects);
      final unpacked = registry.unpackAll(packed);

      expect(unpacked.length, 3);
      expect((unpacked[0]! as _TestDerived1).value, 10);
      expect((unpacked[1]! as _TestDerived2).data, 20);
      expect((unpacked[2]! as _TestDerived1).value, 30);
    });

    test('nested sub-registries with complex types', () {
      final registry = MessagePackRegistry();

      // Sub-registry for shapes
      final shapeRegistry = MessagePackSubRegistry()
          .add<_TestCircle>(
            subId: 1,
            encoder: (circle, reg) => reg.packAll([circle.radius]),
            decoder: (data, reg) {
              final values = reg.unpackAll(data);
              return _TestCircle(values[0]! as double);
            },
          )
          .add<_TestRectangle>(
            subId: 2,
            encoder: (rect, reg) => reg.packAll([rect.width, rect.height]),
            decoder: (data, reg) {
              final values = reg.unpackAll(data);
              return _TestRectangle(
                values[0]! as double,
                values[1]! as double,
              );
            },
          );

      registry.registerSub(50, shapeRegistry);

      final shapes = <_TestShape>[
        _TestCircle(5),
        _TestRectangle(10, 20),
        _TestCircle(3.5),
      ];

      final packed = registry.packAll(shapes);
      final unpacked = registry.unpackAll(packed);

      expect(unpacked.length, 3);
      expect((unpacked[0]! as _TestCircle).radius, 5);
      expect((unpacked[1]! as _TestRectangle).width, 10);
      expect((unpacked[1]! as _TestRectangle).height, 20);
      expect((unpacked[2]! as _TestCircle).radius, 3.5);
    });
  });

  group('MessagePackRegistry cache behavior', () {
    test('clears cache when new extension is registered', () {
      final registry = MessagePackRegistry();

      // First lookup - no extension
      final typeId1 = registry.extTypeForObject(_TestDerived1(1));
      expect(typeId1, isNull);

      // Register extension
      final ext = MessagePackExtension.create<_TestDerived1>(
        typeId: 10,
        encoder: (value, reg) => Uint8List.fromList([value.value]),
        decoder: (data, reg) => _TestDerived1(data[0]),
      );
      registry.register(ext);

      // Second lookup - should find the extension
      final typeId2 = registry.extTypeForObject(_TestDerived1(1));
      expect(typeId2, 10);
    });
  });
}

// Test helper classes
class _TestPerson {
  _TestPerson(this.name, this.age);
  final String name;
  final int age;
}

class _TestAddress {
  _TestAddress(this.street, this.city);
  final String street;
  final String city;
}

class _TestPersonWithAddress {
  _TestPersonWithAddress(this.name, this.address);
  final String name;
  final _TestAddress address;
}

abstract class _TestBase {}

class _TestDerived1 extends _TestBase {
  _TestDerived1(this.value);
  final int value;
}

class _TestDerived2 extends _TestBase {
  _TestDerived2(this.data);
  final int data;
}

class _TestFakeType {}

abstract class _TestShape {}

class _TestCircle extends _TestShape {
  _TestCircle(this.radius);
  final double radius;
}

class _TestRectangle extends _TestShape {
  _TestRectangle(this.width, this.height);
  final double width;
  final double height;
}

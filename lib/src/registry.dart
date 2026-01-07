import 'dart:typed_data';

import 'package:pro_binary/pro_binary.dart';

import 'deserializer.dart';
import 'extension.dart';
import 'serializer.dart';

/// A registry for managing MessagePack extension types.
///
/// The [MessagePackRegistry] allows you to register custom extension encoders
/// and decoders for types that are not natively supported by MessagePack.
/// It implements both [ExtEncoder] and [ExtDecoder] interfaces, making it
/// suitable for use with [Serializer] and [Deserializer].
///
/// Example:
/// ```dart
/// final registry = MessagePackRegistry();
/// // Register a custom extension for DateTime
/// registry.register(
///   MessagePackExtension.create<DateTime>(
///     typeId: 1,
///     encoder: (dt, reg) => Uint8List.fromList(
///       dt.toIso8601String().codeUnits,
///     ),
///     decoder: (data, reg) => DateTime.parse(
///       String.fromCharCodes(data),
///     ),
///   ),
/// );
/// // Use the registry for packing/unpacking
/// final packed = registry.pack(DateTime.now());
/// final unpacked = registry.unpack<DateTime>(packed);
/// ```
class MessagePackRegistry implements ExtEncoder, ExtDecoder {
  /// Creates a new [MessagePackRegistry].
  ///
  /// Optionally accepts a list of [initial] extensions to register immediately.
  /// This is convenient when you have a predefined set of extensions to use.
  ///
  /// Example:
  /// ```dart
  /// final registry = MessagePackRegistry([
  ///   myDateTimeExtension,
  ///   myCustomClassExtension,
  /// ]);
  /// ```
  MessagePackRegistry([List<MessagePackExtension>? initial]) {
    initial?.forEach(register);
  }

  // Internal storage for registered extensions.
  final List<MessagePackExtension> _extensions = [];

  // Maps extension type IDs to their corresponding extensions.
  final Map<int, MessagePackExtension> _decoderMap = {};

  // Cache for mapping runtime types to their extensions.
  final Map<Type, MessagePackExtension?> _typeCache = {};

  /// Registers a MessagePack extension.
  ///
  /// Adds the given [ext] to the registry, making it available for encoding
  /// and decoding operations. Each extension must have a unique `typeId`.
  ///
  /// Throws an [Exception] if an extension with the same `typeId` is already
  /// registered.
  ///
  /// Returns this registry instance to allow method chaining.
  ///
  /// Example:
  /// ```dart
  /// registry.register(myExtension)
  ///   .register(anotherExtension);
  /// ```
  MessagePackRegistry register(MessagePackExtension ext) {
    if (_decoderMap.containsKey(ext.typeId)) {
      throw Exception('Extension with typeId ${ext.typeId} already registered');
    }

    _extensions.add(ext);

    _decoderMap[ext.typeId] = ext;
    _typeCache.clear();
    // Allow method chaining
    // ignore: avoid_returning_this
    return this;
  }

  /// Registers a sub-registry as a single extension type.
  ///
  /// This method allows you to organize multiple related types under a single
  /// extension [typeId]. The [sub] registry handles dispatching to the
  /// appropriate encoder/decoder based on the runtime type.
  ///
  /// This is useful when you have a family of related types (e.g., different
  /// kinds of geometric shapes, event types, etc.) that you want to group
  /// together.
  ///
  /// Returns this registry instance to allow method chaining.
  ///
  /// Example:
  /// ```dart
  /// final shapeRegistry = MessagePackSubRegistry<Shape>()
  ///   .add<Circle>(
  ///     subId: 1,
  ///     encoder: (circle, reg) => encodeCircle(circle),
  ///     decoder: (data, reg) => decodeCircle(data),
  ///   )
  ///   .add<Rectangle>(
  ///     subId: 2,
  ///     encoder: (rect, reg) => encodeRectangle(rect),
  ///     decoder: (data, reg) => decodeRectangle(data),
  ///   );
  ///
  /// registry.registerSub(100, shapeRegistry);
  /// ```
  MessagePackRegistry registerSub(int typeId, MessagePackSubRegistry sub) =>
      register(sub.toExtension(typeId));

  /// Packs multiple objects into a MessagePack-encoded [Uint8List].
  ///
  /// Serializes each value in [values] sequentially into a single byte buffer.
  /// This is more efficient than calling [pack] multiple times because it
  /// reuses the same serializer instance.
  ///
  /// The resulting buffer can be unpacked using [unpackAll].
  ///
  /// Example:
  /// ```dart
  /// final data = registry.packAll([1, 'hello', true, null]);
  /// final values = registry.unpackAll(data); // [1, 'hello', true, null]
  /// ```
  @pragma('vm:prefer-inline')
  Uint8List packAll(List<Object?> values) {
    final s = Serializer(extEncoder: this);
    // Optimize for-loop to avoid closure allocation
    // ignore: prefer_foreach
    for (final value in values) {
      s.encode(value);
    }

    return s.takeBytes();
  }

  /// Unpacks multiple MessagePack-encoded objects from [data].
  ///
  /// Deserializes all values from the given byte buffer that was created
  /// using [packAll]. The method reads values sequentially until all bytes
  /// in the buffer are consumed.
  ///
  /// Returns a list containing all decoded values in the order they were
  /// encoded.
  ///
  /// Example:
  /// ```dart
  /// final data = registry.packAll([1, 'hello', true]);
  /// final values = registry.unpackAll(data); // [1, 'hello', true]
  /// ```
  @pragma('vm:prefer-inline')
  List<Object?> unpackAll(Uint8List data) {
    final d = Deserializer(data, extDecoder: this);
    final results = <Object?>[];
    while (d.hasBytesAvailable) {
      results.add(d.decode());
    }

    return results;
  }

  /// Packs a single object into a MessagePack-encoded [Uint8List].
  ///
  /// Serializes [value] using this registry's extensions. If [value] is a
  /// custom type, it must have a registered extension, otherwise encoding
  /// will fail.
  ///
  /// The type parameter [T] is optional but can be useful for type inference.
  ///
  /// Returns a byte buffer containing the encoded value.
  ///
  /// Example:
  /// ```dart
  /// final data = registry.pack(myCustomObject);
  /// ```
  @pragma('vm:prefer-inline')
  Uint8List pack<T>(T? value) {
    final s = Serializer(extEncoder: this)..encode(value);

    return s.takeBytes();
  }

  /// Unpacks a single MessagePack-encoded object from [data].
  ///
  /// Deserializes a value from the given byte buffer that was created using
  /// [pack]. The type parameter [T] allows you to specify the expected return
  /// type for better type safety.
  ///
  /// Returns the decoded value cast to type [T], or `null` if the encoded
  /// value was `null`.
  ///
  /// Example:
  /// ```dart
  /// final data = registry.pack(myCustomObject);
  /// final decoded = registry.unpack<MyCustomClass>(data);
  /// ```
  @pragma('vm:prefer-inline')
  T? unpack<T>(Uint8List data) {
    final d = Deserializer(data, extDecoder: this);

    return d.decode() as T?;
  }

  /// Finds the extension type ID for the given [object].
  ///
  /// Returns the type ID of the first registered extension that can handle
  /// [object], or `null` if no suitable extension is found.
  ///
  /// This method uses caching to improve performance for repeated lookups
  /// of the same runtime type.
  @override
  int? extTypeForObject(Object? object) {
    if (object == null) {
      return null;
    }

    final type = object.runtimeType;

    final ext = _typeCache[type];
    if (ext != null) {
      return ext.typeId;
    }

    for (var i = 0; i < _extensions.length; i++) {
      final e = _extensions[i];

      if (e.canHandle(object)) {
        _typeCache[type] = e;
        return e.typeId;
      }
    }

    return null;
  }

  /// Encodes an object using the appropriate registered extension.
  ///
  /// Finds the extension for [object] and uses it to encode the value.
  /// Throws an [Exception] if no suitable encoder is registered.
  @override
  Uint8List encodeObject(Object? object) {
    final typeId = extTypeForObject(object);
    if (typeId == null) {
      throw Exception('No encoder for ${object.runtimeType}');
    }
    return _decoderMap[typeId]!.encode(object, this);
  }

  /// Decodes an object from [data] using the extension with [extType].
  ///
  /// Throws an [Exception] if no extension with the given [extType] is
  /// registered.
  @override
  Object? decodeObject(int extType, Uint8List data) {
    final ext = _decoderMap[extType];
    if (ext == null) {
      throw Exception('No decoder for extension $extType');
    }
    return ext.decode(data, this);
  }
}

/// Internal type alias for decoder function maps.
typedef _DecoderMap =
    Map<int, Object? Function(Uint8List, MessagePackRegistry)>;

/// Internal type alias for encoder function maps.
typedef _EncoderMap =
    Map<int, Uint8List Function(Object?, MessagePackRegistry)>;

/// A sub-registry for organizing related MessagePack extension types.
///
/// [MessagePackSubRegistry] allows you to group multiple related types under
/// a single extension type ID. This is useful when you have a family of types
/// that share a common base class or interface.
///
/// The type parameter [Base] specifies the common base type for all registered
/// subtypes. Each subtype is assigned a unique `subId` within this registry.
///
/// When encoding, the registry automatically determines which subtype encoder
/// to use based on the runtime type. The `subId` is encoded along with the
/// data, allowing the correct decoder to be selected during deserialization.
///
/// Example:
/// ```dart
/// // Define a base type and subtypes
/// abstract class Animal {}
/// class Dog extends Animal { String name; Dog(this.name); }
/// class Cat extends Animal { int lives; Cat(this.lives); }
/// // Create a sub-registry for animals
/// final animalRegistry = MessagePackSubRegistry<Animal>()
///   .add<Dog>(
///     subId: 1,
///     encoder: (dog, reg) => Uint8List.fromList(
///       dog.name.codeUnits,
///     ),
///     decoder: (data, reg) => Dog(
///       String.fromCharCodes(data),
///     ),
///   )
///   .add<Cat>(
///     subId: 2,
///     encoder: (cat, reg) => Uint8List.fromList([cat.lives]),
///     decoder: (data, reg) => Cat(data[0]),
///   );
/// // Register with main registry
/// final mainRegistry = MessagePackRegistry()
///   .registerSub(100, animalRegistry);
/// // Use it
/// final data = mainRegistry.pack<Animal>(Dog('Rex'));
/// final animal = mainRegistry.unpack<Animal>(data); // Returns Dog instance
/// ```
class MessagePackSubRegistry<Base> {
  final Map<Type, int> _typeToId = {};

  final _DecoderMap _decoders = {};
  final _EncoderMap _encoders = {};

  /// Adds a subtype to this registry.
  ///
  /// Registers encoding and decoding functions for type [T], which must be
  /// a subtype of [Base]. Each subtype is identified by a unique [subId]
  /// within this sub-registry.
  ///
  /// The [encoder] function should serialize an instance of [T] into a
  /// [Uint8List]. It receives the value and the main [MessagePackRegistry],
  /// allowing nested encoding of complex types.
  ///
  /// The [decoder] function should deserialize a [Uint8List] back into an
  /// instance of [T]. It also receives the main registry for nested decoding.
  ///
  /// Returns this sub-registry instance to allow method chaining.
  ///
  /// Example:
  /// ```dart
  /// registry.add<Circle>(
  ///   subId: 1,
  ///   encoder: (circle, reg) => {
  ///     // Encode circle properties
  ///     final writer = BinaryWriter()
  ///       ..writeFloat64(circle.radius);
  ///     return writer.takeBytes();
  ///   },
  ///   decoder: (data, reg) {
  ///     // Decode circle properties
  ///     final reader = BinaryReader(data);
  ///     return Circle(reader.readFloat64());
  ///   },
  /// );
  /// ```
  MessagePackSubRegistry<Base> add<T>({
    required int subId,
    required Uint8List Function(T value, MessagePackRegistry reg) encoder,
    required T Function(Uint8List data, MessagePackRegistry reg) decoder,
  }) {
    _typeToId[T] = subId;
    _encoders[subId] = (v, reg) => encoder(v as T, reg);
    _decoders[subId] = (d, reg) => decoder(d, reg);
    // Allow method chaining
    // ignore: avoid_returning_this
    return this;
  }

  /// Converts this sub-registry into a [MessagePackExtension].
  ///
  /// Creates a single extension with the given [mainTypeId] that internally
  /// dispatches to the appropriate subtype encoder/decoder based on runtime
  /// type and encoded `subId`.
  ///
  /// This method is typically called internally by
  /// [MessagePackRegistry.registerSub] and doesn't need to be called directly
  /// by users.
  ///
  /// The resulting extension encodes the `subId` as a variable-length integer
  /// followed by the subtype-specific payload. During decoding, the `subId`
  /// is read first to determine which decoder to use.
  @pragma('vm:prefer-inline')
  MessagePackExtension toExtension(int mainTypeId) => .create(
    typeId: mainTypeId,
    encoder: (value, registry) {
      final subId = _typeToId[value.runtimeType];
      if (subId == null) {
        throw Exception('Subtype ${value.runtimeType} not registered');
      }

      final payload = _encoders[subId]!(value, registry);
      final writer = BinaryWriterPool.acquire()
        ..writeVarInt(subId)
        ..writeBytes(payload);

      final bytes = writer.toBytes();
      BinaryWriterPool.release(writer);

      return bytes;
    },
    decoder: (data, registry) {
      final reader = BinaryReader(data);
      final subId = reader.readVarInt();
      final payload = reader.readRemainingBytes();

      final decoderFn = _decoders[subId];
      if (decoderFn == null) {
        throw Exception('Unknown subTypeId: $subId');
      }

      return decoderFn(payload, registry) as Base;
    },
  );
}

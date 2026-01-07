import 'dart:typed_data';

import 'registry.dart';

/// Base class for MessagePack extensions that encode and decode custom types.
///
/// MessagePack extensions allow you to serialize and deserialize types that
/// are not natively supported by the MessagePack specification. Each extension
/// is identified by a unique [typeId] in the range -128 to 127.
///
/// To create an extension, you can either:
/// 1. Subclass [MessagePackExtension] and implement all abstract methods
/// 2. Use the [create] factory method for a simpler, functional approach
///
/// Example using the factory method:
/// ```dart
/// final dateTimeExtension = MessagePackExtension.create<DateTime>(
///   typeId: 1,
///   encoder: (dt, registry) {
///     // Convert DateTime to ISO 8601 string and encode as bytes
///     final iso = dt.toIso8601String();
///     return Uint8List.fromList(utf8.encode(iso));
///   },
///   decoder: (data, registry) {
///     // Decode bytes to string and parse as DateTime
///     final iso = utf8.decode(data);
///     return DateTime.parse(iso);
///   },
/// );
/// // Register with a registry
/// final registry = MessagePackRegistry()
///   ..register(dateTimeExtension);
/// // Use it
/// final now = DateTime.now();
/// final packed = registry.pack(now);
/// final unpacked = registry.unpack<DateTime>(packed);
/// ```
/// Example by subclassing:
/// ```dart
/// class UriExtension extends MessagePackExtension {
///   @override
///   int get typeId => 2;
///   /// Determines if this extension can handle encoding [value].
///   @override
///   bool canHandle(Object? value) => value is Uri;
///   /// Encodes [value] into MessagePack extension format.
///   @override
///   Uint8List encode(Object? value, MessagePackRegistry registry) {
///     final uri = value as Uri;
///     return Uint8List.fromList(utf8.encode(uri.toString()));
///   }
///   /// Decodes [data] from MessagePack extension format back into an object.
///   @override
///   Object? decode(Uint8List data, MessagePackRegistry registry) {
///     return Uri.parse(utf8.decode(data));
///   }
/// }
/// ```
abstract class MessagePackExtension {
  /// The unique identifier for this extension type.
  ///
  /// Must be in the range -128 to 127 as per MessagePack specification.
  /// Each extension registered in a [MessagePackRegistry] must have a
  /// unique [typeId].
  ///
  /// The typeId is encoded in the MessagePack format to identify which
  /// extension decoder should be used during deserialization.
  int get typeId;

  /// Determines whether this extension can handle encoding the given [value].
  ///
  /// This method is called by [MessagePackRegistry] to find the appropriate
  /// extension for encoding an object. It should return `true` if this
  /// extension knows how to encode [value], and `false` otherwise.
  ///
  /// Typically implemented as a simple type check:
  /// ```dart
  /// @override
  /// bool canHandle(Object? value) => value is MyCustomType;
  /// ```
  bool canHandle(Object? value);

  /// Encodes [value] into a MessagePack extension format.
  ///
  /// Converts the given [value] into a [Uint8List] byte array. The [registry]
  /// parameter provides access to the parent registry, which is useful if you
  /// need to encode nested objects that may also have custom types.
  ///
  /// The returned byte array contains only the extension payload data, not
  /// the extension header (which includes the typeId and length). The
  /// MessagePack serializer handles adding the proper extension header.
  ///
  /// Example:
  /// ```dart
  /// @override
  /// Uint8List encode(Object? value, MessagePackRegistry registry) {
  ///   final myObj = value as MyClass;
  ///   // Encode the object's properties
  ///   final writer = BinaryWriter()
  ///     ..writeInt32(myObj.id)
  ///     ..writeString(myObj.name);
  ///   return writer.takeBytes();
  /// }
  /// ```
  Uint8List encode(Object? value, MessagePackRegistry registry);

  /// Decodes [data] from MessagePack extension format back into an object.
  ///
  /// Converts the given [data] byte array back into the original object type.
  /// The [registry] parameter provides access to the parent registry for
  /// decoding nested objects.
  ///
  /// The [data] parameter contains only the extension payload, without the
  /// extension header. The MessagePack deserializer has already parsed the
  /// header and extracted the payload.
  ///
  /// Example:
  /// ```dart
  /// @override
  /// Object? decode(Uint8List data, MessagePackRegistry registry) {
  ///   final reader = BinaryReader(data);
  ///   final id = reader.readInt32();
  ///   final name = reader.readString();
  ///   return MyClass(id: id, name: name);
  /// }
  /// ```
  Object? decode(Uint8List data, MessagePackRegistry registry);

  /// Creates a MessagePack extension for type [T] using functional callbacks.
  ///
  /// This is the recommended way to create extensions as it's more concise
  /// than subclassing. The type parameter [T] determines which objects this
  /// extension can handle.
  ///
  /// Parameters:
  /// - [typeId]: The unique identifier for this extension (must be -128 to 127)
  /// - [encoder]: A function that converts a value of type [T] to bytes
  /// - [decoder]: A function that converts bytes back to type [T]
  ///
  /// Both [encoder] and [decoder] receive the parent [MessagePackRegistry],
  /// which can be used to encode/decode nested custom types.
  ///
  /// Example with nested encoding:
  /// ```dart
  /// class Person {
  ///   final String name;
  ///   final DateTime birthDate;
  ///   Person(this.name, this.birthDate);
  /// }
  /// /// Create an extension for Person that uses DateTime extension
  /// final personExtension = MessagePackExtension.create<Person>(
  ///   typeId: 10,
  ///   encoder: (person, registry) {
  ///     // Use registry to encode the DateTime field
  ///     final nameBytes = Uint8List.fromList(utf8.encode(person.name));
  ///     final dateBytes = registry.pack(person.birthDate);
  ///     final writer = BinaryWriter()
  ///       ..writeInt32(nameBytes.length)
  ///       ..writeBytes(nameBytes)
  ///       ..writeBytes(dateBytes);
  ///     return writer.takeBytes();
  ///   },
  ///   decoder: (data, registry) {
  ///     final reader = BinaryReader(data);
  ///     final nameLength = reader.readInt32();
  ///     final nameBytes = reader.readBytes(nameLength);
  ///     final name = utf8.decode(nameBytes);
  ///     // Use registry to decode the DateTime field
  ///     final dateBytes = reader.readRemainingBytes();
  ///     final birthDate = registry.unpack<DateTime>(dateBytes);
  ///     return Person(name, birthDate);
  ///   },
  /// );
  /// ```
  static MessagePackExtension create<T>({
    required int typeId,
    required Uint8List Function(T value, MessagePackRegistry registry) encoder,
    required T Function(Uint8List data, MessagePackRegistry registry) decoder,
  }) => _MessagePackExtensionImpl(
    typeId: typeId,
    canHandleFn: (v) => v is T,
    encodeFn: (v, reg) => encoder(v as T, reg),
    decodeFn: (d, reg) => decoder(d, reg),
  );
}

/// Internal implementation of [MessagePackExtension] created by the factory.
///
/// This class wraps functional callbacks into a proper [MessagePackExtension]
/// implementation. It's used internally by [MessagePackExtension.create].
class _MessagePackExtensionImpl implements MessagePackExtension {
  /// Creates an extension implementation from functional callbacks.
  _MessagePackExtensionImpl({
    required this.typeId,
    required bool Function(Object?) canHandleFn,
    required Uint8List Function(Object?, MessagePackRegistry) encodeFn,
    required Object? Function(Uint8List, MessagePackRegistry) decodeFn,
  }) : _canHandleFn = canHandleFn,
       _encodeFn = encodeFn,
       _decodeFn = decodeFn;

  @override
  final int typeId;

  /// Internal callback for type checking.
  final bool Function(Object?) _canHandleFn;

  /// Internal callback for encoding.
  final Uint8List Function(Object?, MessagePackRegistry) _encodeFn;

  /// Internal callback for decoding.
  final Object? Function(Uint8List, MessagePackRegistry) _decodeFn;

  @override
  bool canHandle(Object? value) => _canHandleFn(value);

  @override
  Uint8List encode(Object? value, MessagePackRegistry registry) =>
      _encodeFn(value, registry);

  @override
  Object? decode(Uint8List data, MessagePackRegistry registry) =>
      _decodeFn(data, registry);
}

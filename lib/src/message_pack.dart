/// High-level MessagePack API with a builder-style interface for extensions.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:pro_binary/pro_binary.dart';

import 'core/deserializer.dart';
import 'core/exception.dart';
import 'core/serializer.dart';

/// A function type that encodes a value of type [T] into bytes.
typedef Encoder<T> = Uint8List Function(T value, MessagePackContext context);

/// A function type that decodes bytes into a value of type [T].
typedef Decoder<T> = T Function(Uint8List data, MessagePackContext context);

/// A context for MessagePack serialization and deserialization.
///
/// This interface is passed to custom encoders and decoders, allowing them
/// to recursively pack and unpack nested objects using the same configuration.
abstract interface class MessagePackContext {
  /// The default constructor for [MessagePackContext].
  const MessagePackContext();

  /// Packs [value] into a MessagePack-encoded [Uint8List].
  Uint8List pack<T>(T value);

  /// Packs a sequence of [values] into a single MessagePack-encoded
  /// [Uint8List].
  Uint8List packAll<T>(Iterable<T> values);

  /// Unpacks a single value of type [T] from the provided [data].
  T unpack<T>(Uint8List data);

  /// Unpacks all consecutive values from [data] into a list of type [T].
  List<T> unpackAll<T>(Uint8List data);
}

/// A class for high-level MessagePack operations with custom extension support.
///
/// [MessagePack] implements the standard Dart [Codec] interface and provides
/// a builder-style API for registering custom extension types and groups.
///
/// Example:
/// ```dart
/// final mpack = MessagePack(extensions: (m) {
///   m.register<MyClass>(
///     extId: 10,
///     encoder: (val, ctx) => ctx.pack(val.toJson()),
///     decoder: (data, ctx) => MyClass.fromJson(ctx.unpack(data)),
///   );
/// });
///
/// final bytes = mpack.encode(myObject);
/// final decoded = mpack.decode(bytes);
/// ```
class MessagePack extends Codec<dynamic, Uint8List>
    implements MessagePackContext, ExtEncoder, ExtDecoder {
  /// Creates a [MessagePack] instance.
  ///
  /// [extensions] is an optional callback for registering custom types.
  /// [defaultBufferSize] determines the initial size for serialization buffers.
  MessagePack({
    void Function(MessagePack)? extensions,
    this.defaultBufferSize = 1024,
  }) : _extensions = [],
       _decoderMap = {},
       _extensionsCache = {} {
    extensions?.call(this);
  }

  /// The default buffer size for serialization.
  final int defaultBufferSize;

  final List<_Extension> _extensions;
  final Map<int, _Extension> _decoderMap;
  final Map<Type, _Extension?> _extensionsCache;

  /// Registers a custom extension for type [T].
  ///
  /// [extId] must be between -128 and 127.
  /// [encoder] and [decoder] are used for conversion.
  ///
  /// Built-in types cannot be registered as extensions.
  void register<T>({
    required int extId,
    required Encoder<T> encoder,
    required Decoder<T> decoder,
  }) {
    _registerInternal<T>(
      extId: extId,
      encoder: encoder,
      decoder: decoder,
      isGroup: false,
    );
  }

  /// Internal method for registering extensions.
  ///
  /// [isGroup] allows broad types (Object, dynamic) when registering a group.
  void _registerInternal<T>({
    required int extId,
    required Encoder<T> encoder,
    required Decoder<T> decoder,
    required bool isGroup,
  }) {
    assert(() {
      const builtinTypes = {
        int,
        String,
        bool,
        double,
        List,
        Map,
        Set,
        Uint8List,
        ByteData,
        DateTime,
        Float,
      };

      bool isBuiltIn(Type type) => builtinTypes.contains(type);

      if (isBuiltIn(T)) {
        throw MessagePackConfigurationException(
          "Type '$T' is a built-in type and cannot be registered as an "
              'extension.',
          'Built-in types are: ${builtinTypes.join(", ")}. '
              'Use a custom wrapper class instead.',
        );
      }

      if (!isGroup) {
        if (T == Object || T == dynamic || <Object?>[] is List<T>) {
          throw MessagePackConfigurationException(
            "Cannot register extension for base type '$T'.",
            'You must specify a concrete custom class. '
                'If you need polymorphism, use registerGroup.',
          );
        }
      }

      return true;
    }(), 'Invalid extension type');

    if (_decoderMap.containsKey(extId)) {
      throw MessagePackConfigurationException(
        'Extension with id $extId already registered.',
        'Use a unique extension ID between -128 and 127.',
      );
    }

    final ext = _Extension(
      id: extId,
      canHandle: (v) => v is T,
      encode: (v, ctx) => encoder(v as T, ctx),
      decode: (d, ctx) => decoder(d, ctx),
    );

    _extensions.add(ext);
    _decoderMap[extId] = ext;
    _extensionsCache.clear();
  }

  /// Registers a group of related types under a single [extId].
  ///
  /// This allows polymorphic types to share a single MessagePack extension ID
  /// by using internal sub-IDs for each specific type.
  ///
  /// Example:
  /// ```dart
  /// mpack.registerGroup<Shape>(
  ///   extId: 20,
  ///   builder: (group) {
  ///     group.add<Circle>(
  ///       subId: 1,
  ///       encoder: (c, ctx) => ctx.pack(c.radius),
  ///       decoder: (d, ctx) => Circle(ctx.unpack(d)),
  ///     );
  ///     group.add<Square>(
  ///       subId: 2,
  ///       encoder: (s, ctx) => ctx.pack(s.side),
  ///       decoder: (d, ctx) => Square(ctx.unpack(d)),
  ///     );
  ///   },
  /// );
  /// ```
  void registerGroup<Base>({
    required int extId,
    required void Function(MessagePackGroup group) builder,
  }) {
    final group = MessagePackGroup();

    builder(group);

    _registerInternal<Base>(
      extId: extId,
      encoder: (value, context) => _enc(value, context, group),
      decoder: (data, context) => _dec(data, context, group) as Base,
      isGroup: true,
    );
  }

  Object? _dec(
    Uint8List data,
    MessagePackContext context,
    MessagePackGroup group,
  ) {
    if (data.isEmpty) {
      throw const MessagePackConfigurationException(
        'Empty group data.',
        'Ensure the encoded group data contains at least a subtype ID. '
            'Check the encoder implementation for this group.',
      );
    }

    final reader = BinaryReader(data);
    final subId = reader.readVarUint();
    final payload = reader.readRemainingBytes();

    return group._decode(subId, payload, context);
  }

  Uint8List _enc(
    Object? value,
    MessagePackContext context,
    MessagePackGroup group,
  ) {
    final (subId, payload) = group._encode(value, context);

    return BinaryWriterPool.withWriter((w) {
      w
        ..writeVarUint(subId)
        ..writeBytes(payload);

      return w.takeBytes();
    }, payload.length + 5);
  }

  @override
  Uint8List pack<T>(T value) {
    final s = Serializer(
      extEncoder: this,
      initialBufferSize: defaultBufferSize,
    );

    try {
      s.encode(value);
      return s.takeBytes();
    } finally {
      s.dispose();
    }
  }

  @override
  Uint8List packAll<T>(Iterable<T> values) {
    final s = Serializer(
      extEncoder: this,
      initialBufferSize: defaultBufferSize,
    );

    try {
      for (final value in values) {
        s.encode(value);
      }

      return s.takeBytes();
    } finally {
      s.dispose();
    }
  }

  @override
  T unpack<T>(Uint8List data) {
    final d = Deserializer(
      data,
      extDecoder: this,
      preserveMapOrder: false,
    );

    return d.decode() as T;
  }

  @override
  List<T> unpackAll<T>(Uint8List data) {
    final d = Deserializer(
      data,
      extDecoder: this,
      preserveMapOrder: false,
    );

    final results = <dynamic>[];
    while (d.hasBytesAvailable) {
      final value = d.decode();
      results.add(value);
    }

    return results as List<T>;
  }

  // Codec implementation
  @override
  Converter<Object?, Uint8List> get encoder => _MessagePackEncoder(this);

  @override
  Converter<Uint8List, Object?> get decoder => _MessagePackDecoder(this);

  // ExtEncoder implementation
  @override
  int? extTypeForObject(Object? object) {
    if (object == null) {
      return null;
    }

    final type = object.runtimeType;
    final cached = _extensionsCache[type];
    if (cached != null) {
      return cached.id;
    }

    for (final ext in _extensions) {
      if (ext.canHandle(object)) {
        _extensionsCache[type] = ext;
        return ext.id;
      }
    }

    return null;
  }

  @override
  Uint8List encodeObject(Object? object) {
    final typeId = extTypeForObject(object);
    if (typeId == null) {
      throw MessagePackUnsupportedTypeException(
        object.runtimeType,
        "No encoder for type '${object.runtimeType}'.",
        'Register an extension for this type before serializing.',
      );
    }

    final ext = _extensionsCache[object.runtimeType];
    return ext!.encode(object, this);
  }

  // ExtDecoder implementation
  @override
  Object? decodeObject(int extType, Uint8List data) {
    final ext = _decoderMap[extType];
    if (ext == null) {
      throw MessagePackConfigurationException(
        'No decoder for extension $extType.',
        'Ensure the extension is registered using register() or '
            'registerGroup().',
      );
    }

    return ext.decode(data, this);
  }
}

class _MessagePackEncoder extends Converter<Object?, Uint8List> {
  _MessagePackEncoder(this._mpack);
  final MessagePack _mpack;

  @override
  Uint8List convert(Object? input) => _mpack.pack(input);
}

class _MessagePackDecoder extends Converter<Uint8List, Object?> {
  _MessagePackDecoder(this._mpack);
  final MessagePack _mpack;

  @override
  Object? convert(Uint8List input) => _mpack.unpack(input);
}

/// A builder for grouping multiple types under a single extension ID.
///
/// This class is used within [MessagePack.registerGroup] to define how
/// different subtypes are encoded and decoded using sub-IDs.
class MessagePackGroup {
  final List<_Extension> _extensions = [];
  final Map<Type, _Extension> _extensionsCache = {};
  final Map<int, _Extension> _decoders = {};

  /// Adds a subtype to the group.
  ///
  /// [subId] is an internal ID used to distinguish types within the group.
  /// [encoder] and [decoder] are used for conversion.
  void add<T>({
    required int subId,
    required Encoder<T> encoder,
    required Decoder<T> decoder,
  }) {
    final ext = _Extension(
      id: subId,
      canHandle: (v) => v is T,
      encode: (v, ctx) => encoder(v as T, ctx),
      decode: (d, ctx) => decoder(d, ctx),
    );

    _extensions.add(ext);
    _decoders[subId] = ext;
    _extensionsCache.clear();
  }

  (int, Uint8List) _encode(Object? value, MessagePackContext context) {
    final type = value.runtimeType;

    var ext = _extensionsCache[type];

    if (ext == null) {
      for (final e in _extensions) {
        if (e.canHandle(value)) {
          ext = e;
          _extensionsCache[type] = e;
          break;
        }
      }
    }

    if (ext == null) {
      throw MessagePackConfigurationException(
        'Subtype $type not registered in group.',
        'Ensure the subtype is added to the group using group.add().',
      );
    }

    return (ext.id, ext.encode(value, context));
  }

  Object? _decode(int id, Uint8List data, MessagePackContext context) {
    final ext = _decoders[id];
    if (ext == null) {
      throw MessagePackConfigurationException(
        'Decoder for subtype id $id not found.',
        'Ensure all subtypes are registered in the group using group.add().',
      );
    }

    return ext.decode(data, context);
  }
}

/// Internal representation of a MessagePack extension.
class _Extension {
  _Extension({
    required this.id,
    required this.canHandle,
    required this.encode,
    required this.decode,
  });

  /// The extension ID (or sub-ID in a group).
  final int id;

  /// A function that checks if this extension can handle the given object.
  final bool Function(Object?) canHandle;

  /// A function that encodes the object into bytes.
  final Encoder<Object?> encode;

  /// A function that decodes bytes into an object.
  final Decoder<Object?> decode;
}

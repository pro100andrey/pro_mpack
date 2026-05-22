import 'dart:convert';
import 'dart:typed_data';

import 'package:pro_binary/pro_binary.dart';

import 'core/deserializer.dart';
import 'core/error.dart';
import 'core/serializer.dart';

typedef Encoder<T> = Uint8List Function(T value, MessagePackContext context);
typedef Decoder<T> = T Function(Uint8List data, MessagePackContext context);

/// Context for MessagePack serialization and deserialization.
///
/// This interface provides methods for packing and unpacking values,
/// allowing custom extension encoders and decoders to recursively
/// process nested data.
abstract interface class MessagePackContext {
  const MessagePackContext();

  /// Packs a single value into a MessagePack-encoded [Uint8List].
  Uint8List pack<T>(T value);

  /// Packs multiple values into a MessagePack-encoded [Uint8List].
  Uint8List packAll<T>(Iterable<T> values);

  /// Unpacks a single value from a MessagePack-encoded [Uint8List].
  T unpack<T>(Uint8List data);

  /// Unpacks all consecutive values from a MessagePack-encoded [Uint8List].
  List<T> unpackAll<T>(Uint8List data);
}

/// A class responsible for encoding and decoding MessagePack data with
/// support for custom extensions.
///
/// [MessagePack] provides a unified, simple interface for MessagePack
/// operations. It supports both declarative (via builder) and
/// imperative (via direct methods) registration of extensions.
class MessagePack extends Codec<dynamic, Uint8List>
    implements MessagePackContext, ExtEncoder, ExtDecoder {
  /// Creates a new [MessagePack] instance.
  ///
  /// The optional [extensions] builder allows for declarative configuration
  /// of custom types and groups.
  MessagePack({
    void Function(MessagePack)? extensions,
    this.defaultBufferSize = 1024,
  }) : _extensions = [],
       _decoderMap = {},
       _extensionsCache = {} {
    extensions?.call(this);
  }

  /// Initial buffer size for serialization.
  final int defaultBufferSize;

  final List<_Extension> _extensions;
  final Map<int, _Extension> _decoderMap;
  final Map<Type, _Extension?> _extensionsCache;

  /// Registers a custom extension for type [T].
  ///
  /// [extId] must be between -128 and 127.
  /// [encoder] converts a value of type [T] to bytes.
  /// [decoder] converts bytes back to a value of type [T].
  void register<T>({
    required int extId,
    required Encoder<T> encoder,
    required Decoder<T> decoder,
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

      if (!isBuiltIn(T)) {
        return true;
      }

      throw ArgumentError(
        "Type '$T' is a built-in type and cannot be registered as an "
        'extension. Built-in types are: ${builtinTypes.join(", ")}. '
        'Use a custom wrapper class instead.',
      );
    }(), 'Invalid extension type');

    if (_decoderMap.containsKey(extId)) {
      throw MessagePackError('Extension with id $extId already registered');
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
  /// This is useful for polymorphism or when you have many related types
  /// and want to save extension IDs.
  void registerGroup<Base>({
    required int extId,
    required void Function(MessagePackGroup group) builder,
  }) {
    final group = MessagePackGroup();

    builder(group);

    register<Base>(
      extId: extId,
      encoder: (value, context) => _enc(value, context, group),
      decoder: (data, context) => _dec(data, context, group) as Base,
    );
  }

  Object? _dec(
    Uint8List data,
    MessagePackContext context,
    MessagePackGroup group,
  ) {
    if (data.isEmpty) {
      throw MessagePackError('Empty group data');
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

    final writer = BinaryWriterPool.acquire(payload.length + 5)
      ..writeVarUint(subId)
      ..writeBytes(payload);

    try {
      return writer.takeBytes();
    } finally {
      BinaryWriterPool.release(writer);
    }
  }

  @override
  Uint8List pack<T>(T value) {
    final s = Serializer(
      extEncoder: this,
      initialBufferSize: defaultBufferSize,
    )..encode(value);

    return s.takeBytes();
  }

  @override
  Uint8List packAll<T>(Iterable<T> values) {
    final s = Serializer(
      extEncoder: this,
      initialBufferSize: defaultBufferSize,
    );

    for (final value in values) {
      s.encode(value);
    }

    final result = s.takeBytes();

    return result;
  }

  @override
  T unpack<T>(Uint8List data) {
    final d = Deserializer(
      data,
      extDecoder: this,
      preserveMapOrder: false,
    );

    final result = d.decode() as T;
    return result;
  }

  @override
  List<T> unpackAll<T>(Uint8List data) {
    final d = Deserializer(
      data,
      extDecoder: this,
      preserveMapOrder: false,
    );

    final results = <Object?>[];
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
      throw Exception('No encoder for ${object.runtimeType}');
    }

    final ext = _extensionsCache[object.runtimeType];
    return ext!.encode(object, this);
  }

  // ExtDecoder implementation
  @override
  Object? decodeObject(int extType, Uint8List data) {
    final ext = _decoderMap[extType];
    if (ext == null) {
      throw Exception('No decoder for extension $extType');
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
class MessagePackGroup {
  final List<_Extension> _extensions = [];
  final Map<Type, _Extension> _extensionsCache = {};
  final Map<int, _Extension> _decoders = {};

  /// Adds a subtype to the group.
  void add<T>({
    required int subId,
    required Encoder<T> encoder,
    required Decoder<T> decoder,
  }) {
    assert(
      T is! int || T is! DateTime,
      'int and DateTime are reserved for built-in extensions',
    );

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
      throw Exception('Subtype $type not registered in group');
    }

    return (ext.id, ext.encode(value, context));
  }

  Object? _decode(int id, Uint8List data, MessagePackContext context) {
    final ext = _decoders[id];
    if (ext == null) {
      throw MessagePackError('Decoder for subtype id $id not found');
    }

    return ext.decode(data, context);
  }
}

class _Extension {
  _Extension({
    required this.id,
    required this.canHandle,
    required this.encode,
    required this.decode,
  });

  final int id;
  final bool Function(Object?) canHandle;
  final Encoder<Object?> encode;
  final Decoder<Object?> decode;
}

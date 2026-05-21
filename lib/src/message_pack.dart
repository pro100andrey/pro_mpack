import 'dart:convert';
import 'dart:typed_data';

import 'deserializer.dart';
import 'serializer.dart';

/// Context for MessagePack serialization and deserialization.
///
/// This interface provides methods for packing and unpacking values,
/// allowing custom extension encoders and decoders to recursively
/// process nested data.
abstract interface class MessagePackContext {
  /// Packs a single value into a MessagePack-encoded [Uint8List].
  Uint8List pack(Object? value);

  /// Packs multiple values into a MessagePack-encoded [Uint8List].
  Uint8List packAll(Iterable<Object?> values);

  /// Unpacks a single value from a MessagePack-encoded [Uint8List].
  T? unpack<T>(Uint8List data);

  /// Unpacks all consecutive values from a MessagePack-encoded [Uint8List].
  List<Object?> unpackAll(Uint8List data);
}

/// A class responsible for encoding and decoding MessagePack data with
/// support for custom extensions.
///
/// [MessagePack] provides a unified, simple interface for MessagePack
/// operations. It supports both declarative (via builder) and
/// imperative (via direct methods) registration of extensions.
class MessagePack extends Codec<Object?, Uint8List>
    implements MessagePackContext, ExtEncoder, ExtDecoder {
  /// Creates a new [MessagePack] instance.
  ///
  /// The optional [extensions] builder allows for declarative configuration
  /// of custom types and groups.
  MessagePack({
    void Function(MessagePack)? extensions,
    this.defaultBufferSize = 1024,
  }) {
    extensions?.call(this);
  }

  /// Initial buffer size for serialization.
  final int defaultBufferSize;

  final List<_Extension> _extensions = [];
  final Map<int, _Extension> _decoderMap = {};
  final Map<Type, _Extension> _extensionsMap = {};
  final Set<Type> _notFoundCache = {};

  /// Registers a custom extension for type [T].
  ///
  /// [extId] must be between -128 and 127.
  /// [encoder] converts a value of type [T] to bytes.
  /// [decoder] converts bytes back to a value of type [T].
  void register<T>({
    required int extId,
    required Uint8List Function(T value, MessagePackContext context) encoder,
    required T Function(Uint8List data, MessagePackContext context) decoder,
  }) {
    if (_decoderMap.containsKey(extId)) {
      throw Exception('Extension with id $extId already registered');
    }

    final ext = _Extension(
      extId: extId,
      canHandle: (v) => v is T,
      encode: (v, ctx) => encoder(v as T, ctx),
      decode: (d, ctx) => decoder(d, ctx),
    );

    _extensions.add(ext);
    _decoderMap[extId] = ext;
    _extensionsMap.clear();
    _notFoundCache.clear();
  }

  /// Registers a group of related types under a single [extId].
  ///
  /// This is useful for polymorphism or when you have many related types
  /// and want to save extension IDs.
  void registerGroup({
    required int extId,
    required void Function(MessagePackGroup group) builder,
  }) {
    final group = MessagePackGroup();
    builder(group);

    register(
      extId: extId,
      encoder: (value, context) {
        final (subId, payload) = group._encode(value, context);

        // Fast path for subId < 128
        if (subId < 128) {
          final result = Uint8List(payload.length + 1);
          result[0] = subId;
          result.setRange(1, result.length, payload);
          return result;
        }

        // Support for larger subIds if needed
        throw UnimplementedError('subId >= 128 not yet supported in groups');
      },
      decoder: (data, context) {
        if (data.isEmpty) {
          throw Exception('Empty group data');
        }
        final subId = data[0];
        final payload = Uint8List.sublistView(data, 1);
        return group._decode(subId, payload, context);
      },
    );
  }

  /// Creates and returns a group without registering it immediately.
  /// Useful for imperative style.
  MessagePackGroup createGroup({required int extId}) {
    final group = MessagePackGroup();
    register(
      extId: extId,
      encoder: (value, context) {
        final (subId, payload) = group._encode(value, context);
        if (subId < 128) {
          final result = Uint8List(payload.length + 1);
          result[0] = subId;
          result.setRange(1, result.length, payload);
          return result;
        }
        throw UnimplementedError('subId >= 128 not supported');
      },
      decoder: (data, context) {
        final subId = data[0];
        final payload = Uint8List.sublistView(data, 1);
        return group._decode(subId, payload, context);
      },
    );
    return group;
  }

  @override
  Uint8List pack(Object? value) => (Serializer(
    extEncoder: this,
    initialBufferSize: defaultBufferSize,
  )..encode(value)).takeBytes();

  @override
  Uint8List packAll(Iterable<Object?> values) {
    final s = Serializer(
      extEncoder: this,
      initialBufferSize: defaultBufferSize,
    );
    for (final v in values) {
      s.encode(v);
    }
    return s.takeBytes();
  }

  @override
  T? unpack<T>(Uint8List data) =>
      Deserializer(data, extDecoder: this).decode() as T?;

  @override
  List<Object?> unpackAll(Uint8List data) {
    final d = Deserializer(data, extDecoder: this);
    final results = <Object?>[];
    while (d.hasBytesAvailable) {
      results.add(d.decode());
    }
    return results;
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

    final cached = _extensionsMap[type];
    if (cached != null) {
      return cached.extId;
    }
    if (_notFoundCache.contains(type)) {
      return null;
    }

    for (final ext in _extensions) {
      if (ext.canHandle(object)) {
        _extensionsMap[type] = ext;
        return ext.extId;
      }
    }

    _notFoundCache.add(type);
    return null;
  }

  @override
  Uint8List encodeObject(Object? object, ExtEncoder context) {
    final typeId = extTypeForObject(object);
    if (typeId == null) {
      throw Exception('No encoder for ${object.runtimeType}');
    }
    return _decoderMap[typeId]!.encode(object, context as MessagePackContext);
  }

  // ExtDecoder implementation
  @override
  Object? decodeObject(int extType, Uint8List data, ExtDecoder context) {
    final ext = _decoderMap[extType];
    if (ext == null) {
      throw Exception('No decoder for extension $extType');
    }
    return ext.decode(data, context as MessagePackContext);
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
  final Map<Type, int> _typeToId = {};
  final Map<int, Object? Function(Uint8List, MessagePackContext)> _decoders =
      {};
  final Map<int, Uint8List Function(Object?, MessagePackContext)> _encoders =
      {};

  /// Adds a subtype to the group.
  void add<T>({
    required int typeId,
    required Uint8List Function(T value, MessagePackContext context) encoder,
    required T Function(Uint8List data, MessagePackContext context) decoder,
  }) {
    _typeToId[T] = typeId;
    _encoders[typeId] = (v, ctx) => encoder(v as T, ctx);
    _decoders[typeId] = (d, ctx) => decoder(d, ctx);
  }

  (int, Uint8List) _encode(Object? value, MessagePackContext context) {
    final id = _typeToId[value.runtimeType];
    if (id == null) {
      throw Exception('Subtype ${value.runtimeType} not registered');
    }
    return (id, _encoders[id]!(value, context));
  }

  Object? _decode(int id, Uint8List data, MessagePackContext context) {
    final decoder = _decoders[id];
    if (decoder == null) {
      throw Exception('Unknown subId $id');
    }
    return decoder(data, context) ;
  }
}

class _Extension {
  _Extension({
    required this.extId,
    required this.canHandle,
    required this.encode,
    required this.decode,
  });

  final int extId;
  final bool Function(Object?) canHandle;
  final Uint8List Function(Object?, MessagePackContext) encode;
  final Object? Function(Uint8List, MessagePackContext) decode;
}

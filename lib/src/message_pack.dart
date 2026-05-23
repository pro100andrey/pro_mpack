/// High-level MessagePack API with a builder-style interface for extensions.
library;

import 'dart:collection';
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
class MessagePack extends Codec<dynamic, Uint8List>
    implements MessagePackContext, ExtEncoder, ExtDecoder {
  /// Creates a [MessagePack] instance.
  MessagePack({
    void Function(MessagePack)? extensions,
    this.defaultBufferSize = 1024,
  }) : _polymorphic = [],
       _decoderMap = HashMap(),
       _typeMap = HashMap() {
    extensions?.call(this);
  }

  /// The default buffer size for serialization.
  final int defaultBufferSize;

  /// Tier 2: Polymorphic extensions. Results are cached to Tier 1.
  final List<_Extension> _polymorphic;

  /// Map for fast decoder lookup by extension ID.
  final Map<int, _Extension> _decoderMap;

  /// Tier 1: Exact type match map for O(1) performance.
  final Map<Type, _Extension?> _typeMap;

  /// Registers a custom extension for type [T].
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
  void _registerInternal<T>({
    required int extId,
    required Encoder<T> encoder,
    required Decoder<T> decoder,
    required bool isGroup,
  }) {
    assert(() {
      _validateType(T, isGroup);
      return true;
    }(), 'Invalid extension type');

    if (_decoderMap.containsKey(extId)) {
      throw MessagePackConfigurationException(
        'Extension with id $extId already registered.',
        '',
      );
    }

    final ext = _Extension(
      id: extId,
      canHandle: (v) => v is T,
      encode: (v, ctx) => encoder(v as T, ctx),
      decode: (d, ctx) => decoder(d, ctx),
    );

    _decoderMap[extId] = ext;
    _typeMap[T] = ext;
    _polymorphic.add(ext);
  }

  void _validateType(Type type, bool isGroup) {
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

    if (builtinTypes.contains(type)) {
      throw MessagePackConfigurationException(
        "Type '$type' is a built-in type.",
        'Built-in types are: ${builtinTypes.join(", ")}.',
      );
    }

    if (!isGroup) {
      bool isBroadType(Type type) {
        final s = type.toString();
        return s == 'Object?' || s == 'dynamic';
      }

      if (type == Object || type == dynamic || isBroadType(type)) {
        throw MessagePackConfigurationException(
          "Cannot register extension for base type '$type'.",
          'Use registerGroup for polymorphic types.',
        );
      }
    }
  }

  /// Registers a group of related types under a single [extId].
  void registerGroup<Base>({
    required int extId,
    required void Function(MessagePackGroup group) builder,
  }) {
    assert(() {
      _validateType(Base, true);
      return true;
    }(), 'Invalid group base type');

    final group = MessagePackGroup();
    final groupExt = _Extension(
      id: extId,
      canHandle: (v) => v is Base && group.canHandle(v),
      encode: (v, ctx) => _enc(v, ctx, group),
      decode: (d, ctx) => _dec(d, ctx, group) as Base,
    );

    group
      .._groupExtension = groupExt
      .._messagePack = this;

    builder(group);

    if (_decoderMap.containsKey(extId)) {
      throw MessagePackConfigurationException(
        'Id $extId already registered.',
        '',
      );
    }

    _decoderMap[extId] = groupExt;
    _polymorphic.add(groupExt);
    _typeMap[Base] = groupExt;
  }

  Object? _dec(
    Uint8List data,
    MessagePackContext context,
    MessagePackGroup group,
  ) {
    if (data.isEmpty) {
      throw const MessagePackConfigurationException('Empty data.', '');
    }

    final reader = BinaryReader(data);
    return group._decode(
      reader.readVarUint(),
      reader.readRemainingBytes(),
      context,
    );
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
    final d = Deserializer(data, extDecoder: this);
    return d.decode() as T;
  }

  @override
  List<T> unpackAll<T>(Uint8List data) {
    final d = Deserializer(data, extDecoder: this);
    final res = <dynamic>[];
    while (d.hasBytesAvailable) {
      res.add(d.decode());
    }
    return res as List<T>;
  }

  @override
  Converter<Object?, Uint8List> get encoder => _MessagePackEncoder(this);
  @override
  Converter<Uint8List, Object?> get decoder => _MessagePackDecoder(this);

  @override
  int? extTypeForObject(Object? object) {
    if (object == null) {
      return null;
    }

    final type = object.runtimeType;

    if (_typeMap.containsKey(type)) {
      return _typeMap[type]?.id;
    }

    for (final ext in _polymorphic) {
      if (ext.canHandle(object)) {
        _typeMap[type] = ext;
        return ext.id;
      }
    }

    _typeMap[type] = null;
    return null;
  }

  @override
  Uint8List encodeObject(Object? object) {
    if (object == null) {
      throw const MessagePackConfigurationException('Null.', '');
    }

    final type = object.runtimeType;

    if (_typeMap.containsKey(type)) {
      final ext = _typeMap[type];
      if (ext != null) {
        return ext.encode(object, this);
      }
    } else {
      for (final e in _polymorphic) {
        if (e.canHandle(object)) {
          _typeMap[type] = e;
          return e.encode(object, this);
        }
      }
      _typeMap[type] = null;
    }

    throw MessagePackUnsupportedTypeException(type, 'No encoder.', '');
  }

  @override
  Object? decodeObject(int extType, Uint8List data) {
    final ext = _decoderMap[extType];
    if (ext == null) {
      throw const MessagePackConfigurationException('No decoder.', '');
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
  MessagePack? _messagePack;
  _Extension? _groupExtension;

  final List<_Extension> _polymorphic = [];
  final Map<Type, _Extension?> _typeMap = HashMap();
  final Map<int, _Extension> _decoders = HashMap();

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
    _decoders[subId] = ext;

    _typeMap[T] = ext;
    if (_groupExtension != null) {
      _messagePack?._typeMap[T] = _groupExtension;
    }

    final isPoly = T == Object || T == dynamic || <Object?>[] is List<T>;
    if (isPoly) {
      _polymorphic.add(ext);
    }
  }

  bool canHandle(Object? value) {
    if (value == null) {
      return false;
    }

    final type = value.runtimeType;
    if (_typeMap.containsKey(type)) {
      return true;
    }

    for (final ext in _polymorphic) {
      if (ext.canHandle(value)) {
        _typeMap[type] = ext;
        return true;
      }
    }
    return false;
  }

  (int, Uint8List) _encode(Object? value, MessagePackContext context) {
    if (value == null) {
      throw const MessagePackConfigurationException('Null.', '');
    }

    final type = value.runtimeType;

    if (_typeMap.containsKey(type)) {
      final ext = _typeMap[type];
      if (ext != null) {
        return (ext.id, ext.encode(value, context));
      }
    } else {
      for (final e in _polymorphic) {
        if (e.canHandle(value)) {
          _typeMap[type] = e;
          return (e.id, e.encode(value, context));
        }
      }
      _typeMap[type] = null;
    }

    throw MessagePackUnsupportedTypeException(
      type,
      'Subtype $type not registered.',
      '',
    );
  }

  Object? _decode(int id, Uint8List data, MessagePackContext context) {
    final ext = _decoders[id];
    if (ext == null) {
      throw MessagePackConfigurationException('Subtype id $id not found.', '');
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

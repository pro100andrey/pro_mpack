/// High-level MessagePack API — designed for maximum performance and
/// ergonomics.
///
/// This library provides a high-performance MessagePack [Codec] implementation
/// with support for custom extensions, type groups, and advanced performance
/// optimizations like inline caching and zero-allocation buffer management.
///
/// The extension-resolution engine (type→encoder and extId→decoder lookups, the
/// four-layer encode cache, group routing, and cache invalidation) lives in
/// [ExtensionRegistry]; this codec is a thin adapter that drives the
/// [Packer]/[Unpacker] through the registry's bound callbacks.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'core/packer.dart';
import 'core/unpacker.dart';
import 'extension_registry.dart';
import 'stream/transformer.dart';

export 'extension_registry.dart' show Decoder, Encoder, MessagePackGroup;

// Main class

/// A high-performance MessagePack codec with custom extension support.
///
/// Supports standard MessagePack types and provides a flexible API for
/// registering custom extensions and grouped types.
///
/// Example:
/// ```dart
/// final mp = MessagePack(
///   extensions: (mp) {
///     mp.register<BigInt>(
///       extId: 1,
///       encoder: (v, p) => p.packString(v.toString()),
///       decoder: (u, l) => BigInt.parse(u.unpackString()!),
///     );
///   },
/// );
///
/// final bytes = mp.pack(BigInt.from(42));
/// final value = mp.unpack<BigInt>(bytes);
/// ```
class MessagePack extends Codec<dynamic, Uint8List> {
  /// Creates a [MessagePack] instance.
  ///
  /// * [extensions]: Optional callback to register custom types during
  ///   initialization.
  /// * [bufferSize]: Initial buffer capacity for the internal [Packer].
  ///   Defaults to 1024.
  /// * [allowOverwrite]: If `true`, allows re-registering the same type or
  ///   extension ID. If `false` (default), throws a [
  ///   MessagePackConfigurationException] on duplicates. Enabling this will
  ///   clear internal caches when a type is re-registered.
  MessagePack({
    void Function(MessagePack mp)? extensions,
    this.bufferSize = 1024,
    bool allowOverwrite = false,
  }) : _registry = ExtensionRegistry(allowOverwrite: allowOverwrite) {
    extensions?.call(this);
  }

  /// Default buffer capacity for the internal serializer.
  final int bufferSize;

  /// Owns extension resolution and its caches.
  final ExtensionRegistry _registry;

  // Codec converters — created once.
  late final _enc = _MessagePackEncoder(this);
  late final _dec = _MessagePackDecoder(this);

  /// Exposes the encoder converter for use in standard Dart APIs.
  @override
  Converter<dynamic, Uint8List> get encoder => _enc;

  /// Exposes the decoder converter for use in standard Dart APIs.
  @override
  Converter<Uint8List, dynamic> get decoder => _dec;

  /// Returns a [StreamTransformer] that decodes a stream of MessagePack bytes
  /// into a stream of objects.
  StreamTransformer<List<int>, dynamic> get streamDecoder =>
      MessagePackStreamTransformer(this);

  // Registration

  /// Registers a custom extension for type [T].
  ///
  /// [extId] must be in the MessagePack range (-128..127) and unique unless
  /// `allowOverwrite` is enabled.
  ///
  /// Example:
  /// ```dart
  /// mp.register<Color>(
  ///   extId: 10,
  ///   encoder: (c, ctx) => ctx.pack(c.value),
  ///   decoder: (d, ctx) => Color(ctx.unpack<int>(d)),
  /// );
  /// ```
  void register<T>({
    required int extId,
    required Encoder<T> encoder,
    required Decoder<T> decoder,
    bool polymorphic = false,
  }) => _registry.register<T>(
    extId: extId,
    encoder: encoder,
    decoder: decoder,
    polymorphic: polymorphic,
  );

  /// Registers a group of related types under a single [extId].
  ///
  /// Each type in the group gets a unique `subId` (integer). The `subId` is
  /// automatically prepended to the encoded payload.
  ///
  /// Benefits:
  /// - **ID conservation**: Uses only one extension ID for multiple types.
  /// - **Performance**: Grouped types use the same high-performance routing
  ///   logic as standalone extensions.
  ///
  /// Example:
  /// ```dart
  /// mp.registerGroup(
  ///   extId: 2,
  ///   builder: (g) {
  ///     g.add<Circle>(
  ///       subId: 1,
  ///       encoder: (c, p) => p.packDouble(c.radius),
  ///       decoder: (u, l) => Circle(u.unpackDouble()!),
  ///     );
  ///     g.add<Rectangle>(
  ///       subId: 2,
  ///       encoder: (r, p) => p.packAll([r.w, r.h]),
  ///       decoder: (u, l) {
  ///         final w = u.unpackDouble()!;
  ///         final h = u.unpackDouble()!;
  ///         return Rectangle(w, h);
  ///       },
  ///     );
  ///   },
  /// );
  /// ```
  void registerGroup({
    required int extId,
    required void Function(MessagePackGroup group) builder,
  }) => _registry.registerGroup(extId: extId, builder: builder);

  // Pack / Unpack

  /// Encodes [value] into MessagePack bytes.
  @pragma('vm:prefer-inline')
  Uint8List pack(dynamic value) => Packer.encode(
    value,
    encodeExt: _registry.encodeExt,
    initialBufferSize: bufferSize,
  );

  /// Decodes a single value of type [T] from [data].
  @pragma('vm:prefer-inline')
  T unpack<T>(Uint8List data) =>
      Unpacker(buffer: data, decodeExt: _registry.decodeExt).unpack() as T;

  /// Encodes a sequence of [values] into a single MessagePack buffer.
  ///
  /// The values are concatenated without a top-level array, mirroring the
  /// top-level `serializeAll` but resolving custom types through this codec's
  /// registered extensions. The bytes are identical to calling [pack] on each
  /// value and concatenating the results.
  @pragma('vm:prefer-inline')
  Uint8List packAll(Iterable<dynamic> values) => Packer.encodeAll(
    values,
    encodeExt: _registry.encodeExt,
    initialBufferSize: bufferSize,
  );

  /// Decodes every MessagePack value in [data] into a list.
  ///
  /// Mirrors the top-level `deserializeAll` but resolves custom extension types
  /// through this codec's registered extensions. Useful for buffers produced by
  /// [packAll].
  @pragma('vm:prefer-inline')
  List<dynamic> unpackAll(Uint8List data) {
    final u = Unpacker(buffer: data, decodeExt: _registry.decodeExt);
    final result = <dynamic>[];

    while (u.hasBytesAvailable) {
      result.add(u.unpack());
    }

    return result;
  }
}

// Codec adapters

/// Internal converter for encoding objects to MessagePack bytes.
class _MessagePackEncoder extends Converter<dynamic, Uint8List> {
  _MessagePackEncoder(this._mp);

  final MessagePack _mp;

  @override
  @pragma('vm:prefer-inline')
  Uint8List convert(dynamic input) => _mp.pack(input);
}

/// Internal converter for decoding MessagePack bytes to objects.
class _MessagePackDecoder extends Converter<Uint8List, dynamic> {
  _MessagePackDecoder(this._mp);

  final MessagePack _mp;

  @override
  @pragma('vm:prefer-inline')
  dynamic convert(Uint8List input) => _mp.unpack<dynamic>(input);
}

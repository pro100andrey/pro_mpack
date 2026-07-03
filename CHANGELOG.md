<!-- markdownlint-disable-file MD025 -->
# 3.1.1

- **Update**: Updated dependencies to the latest versions to ensure compatibility and stability.

# 3.1.0

- **Feat**: Incremental (field-by-field) codec primitives. `Packer.packMapLength` / `packArrayLength` write just a collection header, and `Unpacker.unpackMapLength` / `unpackArrayLength` read just the count — so a schema-driven generator can encode/decode a struct one entry at a time with the typed packers, with no intermediate `Map`/`List`. `Unpacker.skip()` advances past one complete value (recursively), letting decoders drop unknown fields for forward compatibility.
- **Feat**: `MessagePack.packAll` / `unpackAll` — registry-aware encoding/decoding of multiple values per buffer (the codec-instance counterpart of the top-level `serializeAll` / `deserializeAll`).
- **Feat**: `Unpacker.unpackMapOf<K, V>()` — typed map decode, mirroring `unpackArrayOf<T>()`.
- **Feat**: `Packer.encode` / `encodeAll` — static helpers that own the buffer-pool lifecycle (acquire → pack → release), used by `serialize`, `serializeAll`, `MessagePack.pack` and `packAll`.
- **Performance**: Strings are encoded in a single UTF-8 pass via the Reserve & Backpatch pattern (previously the string was scanned twice — once to size the header, once to write). No change for short/ASCII strings; a clear win on long strings.
- **Internal**: Behaviour-preserving consolidation of the core — one home each for the wire-format grammar (shared by `Unpacker.skip()` and `MessagePackScanner`), the Timestamp codec, the ext-header format table, and the extension registry (`ExtensionRegistry`). Encoded bytes and decoded values are byte-for-byte identical; the decode hot path is unchanged and allocation-free.
- **Examples / Docs**: New [Incremental Codecs](example/incremental/) example and README recipe covering the field-by-field primitives.

All changes are additive — no existing signatures, encoded bytes, or documented behaviour change.

# 3.0.0+1

- **Fix**: README.md

# 3.0.0

- **Feat**: Introduced zero-allocation streaming capabilities. Added `MessagePackStreamTransformer` (`streamDecoder`) to seamlessly reconstruct fragmented chunks byte-by-byte without allocating temporary buffers.
- **Feat**: Massive API modernization. Introduced `MessagePackScanner` as an abstract final class, replaced `Object` with `dynamic` for better type flexibility, added `unpackAs<T>()`, and added configuration for `allowOverwrite` and `unhandledTypes`.
- **Performance**: Significant performance improvements across the entire encoder and decoder. Eliminated temporary memory allocations for extension packing by implementing the *Reserve & Backpatch* pattern.
- **Examples**: Replaced simple examples with four robust, real-world runnable architectures: Basic Usage, Extensions in Depth, Advanced Network Streaming, and Big Data File Streaming.
- **Docs**: Completely restructured the main `README.md` and inline documentation.
- **Fix**: Resolved internal type-checking bugs in `_checkType<T>()` and other minor edge-cases.

# 2.1.0

- **Feat**: Introduced a high-level `MessagePack` API (`lib/src/message_pack.dart`) offering a builder-style interface. This includes support for declarative and imperative custom extensions, polymorphic group registration (`registerGroup`), and seamless integration with the Dart `Codec` interface.
- **Feat**: Added a new robust and exhaustive `MessagePackException` hierarchy (`lib/src/core/exception.dart`) for granular error handling.
- Update dependencies to the latest versions

# 2.0.2

- Update dependencies to the latest versions

# 2.0.1

- Update dependencies to the latest versions

# 2.0.0

- Update dependencies to the latest versions, min sdk: ^3.6.0

# 1.1.1

- Update dependencies to the latest versions to ensure compatibility and stability.

# 1.1.0

- Fix: Expanded test coverage to improve validation across a broader range of edge cases, enhancing overall reliability.
- Fix: Resolved test failures following dependency updates, ensuring compatibility and stability with the latest versions.
- Docs: Updated documentation to include new properties.
- Feat: Added initialBufferSize parameter to the serializer constructor, enabling customized buffer size for optimized memory management.
- Update: Updated dependencies to the latest versions to ensure compatibility and stability.

# 1.0.2

- Update documentation.
- Update dependencies.

# 1.0.1

- Update documentation.

# 1.0.0

- Initial version.

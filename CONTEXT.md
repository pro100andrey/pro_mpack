# pro_mpack — Domain Glossary

The ubiquitous language for this MessagePack codec. Use these terms exactly in
issues, PRDs, tests, and code comments; avoid the listed synonyms.

## Core

- **Wire-format grammar** — the mapping from a MessagePack header byte to "which
  type, and how many length bytes / sub-elements follow". The deepest knowledge in
  the package. Lives (post-3.1) in one shared monomorphic lookup table (`mpShapes`,
  built once at load) consulted by both skip-walkers. _Avoid_: "parser rules",
  "format spec" (the spec is the external document; the grammar is our in-code
  table).

- **Packer** — the low-level MessagePack serializer (`extension type` over a
  `BinaryWriter`). Encodes Dart objects to bytes via typed `packX` methods plus the
  generic `pack`.

- **Unpacker** — the low-level MessagePack deserializer (`extension type` over a
  `BinaryReader`). Two entry points over the grammar: `unpack()` **materializes** a
  value; `skip()` **advances** past one value without materializing.

- **Scanner** — `MessagePackScanner`, a zero-allocation walk over the grammar on the
  streaming reader (`StreamBinaryReader`) that measures/skips one value to find
  message boundaries. Shares the grammar with `Unpacker`; the readers stay separate.

## Extensions

- **Extension seam** — the `EncodeExt`/`DecodeExt` callback pair through which every
  non-built-in type is encoded/decoded. The single place custom types cross into the
  `Packer`/`Unpacker`.

- **Extension registry** — `ExtensionRegistry`, the internal module owning type→
  encoder and extId→decoder resolution: the 4-layer encode cache (inline cache, flat
  map, negative cache, polymorphic fallback memoization), group routing, and cache
  invalidation on overwrite. Exposed to `Packer`/`Unpacker` only as the bound
  `EncodeExt`/`DecodeExt` callbacks. Public-named (so it is directly testable) but
  not exported from `pro_mpack.dart`. _Avoid_: "extension manager", "type map".

- **Internal extension record** — `_Ext`, the erased record holding an extension's
  id, optional subId, `canHandle`, `encode`, `decode`. Built by one factory inside the
  registry.

- **Group** — a set of related types sharing one extension id, disambiguated by a
  `subId` prepended to the payload (`registerGroup` / `MessagePackGroup`).

- **Timestamp codec** — the one built-in extension (`extType -1`), owning
  `DateTime`↔bytes across TS32/TS64/TS96. **Core-dispatched, not user-registered** —
  bare `Packer`/`Unpacker` and `serialize` handle `DateTime` with no `MessagePack`
  instance present.

## Framing

- **Ext-header** — the marker + header-size selection for an extension payload of a
  given length (`fixext1/2/4/8/16`, `ext8/16/32`). One format table, consulted by both
  ext write strategies.

- **Reserve & backpatch** — the zero-allocation header-sizing pattern: reserve the max
  header, write the payload, measure it, pick the smallest header, shift the payload
  back, write the header in place. Used by `packExt` and (post-3.1) by single-pass
  string encode.

## Two-tier public API

- **Top-level functions** — `serialize`/`serializeAll`/`deserialize`/`deserializeAll`:
  the zero-config quick path (no registered extensions, or a one-off raw callback).
- **`MessagePack`** — the configured, registry-aware `Codec` for custom extensions and
  groups. Both tiers are first-class and coexist by design; neither supersedes the
  other.

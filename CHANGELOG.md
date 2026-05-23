## 2.2.0

- **Fix**: Added explicit `sec >= 0` check in timestamp serializer (`writeTimestamp`) to ensure MessagePack spec compliance for 64-bit timestamp format (unsigned 34-bit seconds field). Negative seconds (pre-1970 dates) now correctly route to 96-bit timestamp format.
- **Test**: Added comprehensive timestamp serialization tests covering TS96 (pre-1970 dates, byte-order verification) and TS64 (post-1970 with nanoseconds, data64 layout validation).


## 2.1.0

- **Feat**: Introduced a high-level `MessagePack` API (`lib/src/message_pack.dart`) offering a builder-style interface. This includes support for declarative and imperative custom extensions, polymorphic group registration (`registerGroup`), and seamless integration with the Dart `Codec` interface.
- **Feat**: Added a new robust and exhaustive `MessagePackException` hierarchy (`lib/src/core/exception.dart`) for granular error handling.
- Update dependencies to the latest versions

## 2.0.2

- Update dependencies to the latest versions

## 2.0.1

- Update dependencies to the latest versions

## 2.0.0

- Update dependencies to the latest versions, min sdk: ^3.6.0

## 1.1.1

- Update dependencies to the latest versions to ensure compatibility and stability.

## 1.1.0

- Fix: Expanded test coverage to improve validation across a broader range of edge cases, enhancing overall reliability.
- Fix: Resolved test failures following dependency updates, ensuring compatibility and stability with the latest versions.
- Docs: Updated documentation to include new properties.
- Feat: Added initialBufferSize parameter to the serializer constructor, enabling customized buffer size for optimized memory management.
- Update: Updated dependencies to the latest versions to ensure compatibility and stability.

## 1.0.2

- Update documentation.
- Update dependencies.

## 1.0.1

- Update documentation.

## 1.0.0

- Initial version.

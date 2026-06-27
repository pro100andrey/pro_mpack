import 'dart:typed_data';

import 'package:pro_mpack/pro_mpack.dart';
import 'package:pro_mpack/src/extension_registry.dart';
import 'package:test/test.dart';

/// A trivial sealed-ish value used to exercise polymorphic fallback. Its
/// `runtimeType` is exactly `_Boxed`, registered directly.
class _Boxed {
  const _Boxed(this.value);
  final int value;
}

/// Base type whose concrete instances have a different `runtimeType`, used to
/// exercise the polymorphic fallback + memoization path.
abstract class _Animal {
  int get legs;
}

class _Dog implements _Animal {
  @override
  int get legs => 4;
}

void main() {
  group('ExtensionRegistry (direct seam)', () {
    /// Encodes [value] through the registry's bound callback, returning whether
    /// it was handled and the bytes written.
    (bool, Uint8List) encode(ExtensionRegistry r, Object? value) {
      final p = Packer(encodeExt: r.encodeExt);
      final handled = r.encodeExt(value, p);
      return (handled, p.takeBytes());
    }

    test('negative cache records unregistered types', () {
      final r = ExtensionRegistry();
      expect(r.isUnhandled(_Boxed), isFalse);

      final (handled, _) = encode(r, const _Boxed(1));
      expect(handled, isFalse);
      expect(r.isUnhandled(_Boxed), isTrue, reason: 'cached as unsupported');

      // A second attempt stays unhandled (served from the negative cache).
      final (handled2, _) = encode(r, const _Boxed(2));
      expect(handled2, isFalse);
    });

    test('polymorphic fallback memoizes the concrete runtimeType', () {
      final r = ExtensionRegistry()
        ..register<_Animal>(
          extId: 1,
          polymorphic: true,
          encoder: (a, p) => p.packInt(a.legs),
          decoder: (u, l) => _Dog(),
        );

      expect(r.fallbackCount, 1);
      // _Dog is not registered directly — only the _Animal fallback is.
      expect(r.hasCachedType(_Dog), isFalse);

      final (handled, bytes) = encode(r, _Dog());
      expect(handled, isTrue);
      expect(bytes.isNotEmpty, isTrue);

      // After the first successful fallback, the concrete runtimeType is cached
      // for O(1) lookups.
      expect(r.hasCachedType(_Dog), isTrue, reason: 'memoized after first hit');
      expect(r.lastResolvedType, _Dog);
    });

    test('overwrite swaps the encoder and clears the inline cache', () {
      final r = ExtensionRegistry(allowOverwrite: true)
        ..register<_Boxed>(
          extId: 1,
          encoder: (b, p) => p.packInt(b.value),
          decoder: (u, l) => const _Boxed(0),
        );

      final (_, before) = encode(r, const _Boxed(7));
      expect(r.hasCachedType(_Boxed), isTrue);
      expect(r.lastResolvedType, _Boxed);

      // Re-register the same type with a different encoder.
      r.register<_Boxed>(
        extId: 1,
        encoder: (b, p) => p.packString('boxed'),
        decoder: (u, l) => const _Boxed(0),
      );

      // Overwriting a registered type clears the inline cache.
      expect(r.lastResolvedType, isNull);

      // The new encoder is now used — different bytes for the same value.
      final (handled, after) = encode(r, const _Boxed(7));
      expect(handled, isTrue);
      expect(
        after,
        isNot(equals(before)),
        reason: 'new encoder produces different bytes',
      );
    });

    test('duplicate registration without overwrite throws', () {
      final r = ExtensionRegistry()
        ..register<_Animal>(
          extId: 1,
          encoder: (a, p) => p.packInt(a.legs),
          decoder: (u, l) => _Dog(),
        );

      expect(
        () => r.register<_Animal>(
          extId: 2,
          encoder: (a, p) => p.packInt(a.legs),
          decoder: (u, l) => _Dog(),
        ),
        throwsA(isA<MessagePackConfigurationException>()),
      );
    });
  });
}

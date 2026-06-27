/// The Timestamp codec — the MessagePack Timestamp extension (`extType -1`),
/// one home for both directions.
///
/// Public-named so the core can dispatch to it, but not exported from
/// `pro_mpack.dart`; it is not part of the public API.
///
/// This is the single built-in extension. Unlike user extensions it is
/// dispatched directly by the core `Packer`/`Unpacker` (and therefore by
/// `serialize`/`serializeAll` and the bare codecs) so that `DateTime`
/// round-trips with no `MessagePack` instance present. It owns the
/// TS32/TS64/TS96 encode and their decode inverses together, so the
/// format-selection rules and their readers stay in one place.
library;

import 'package:pro_binary/pro_binary.dart';

import 'constants.dart';
import 'exception.dart';

/// Encodes and decodes `DateTime` as the MessagePack timestamp extension.
abstract final class MessagePackTimestamp {
  MessagePackTimestamp._();

  /// Encodes [value] into [wr] using the standard MessagePack timestamp
  /// extension, automatically choosing the smallest valid format
  /// (TS32, TS64, or TS96) based on range and precision.
  static void encode(BinaryWriter wr, DateTime value) {
    final micro = (value.isUtc ? value : value.toUtc()).microsecondsSinceEpoch;
    const million = 1_000_000;
    final sec = (micro / million).floor();
    final nano = ((micro % million + million) % million) * 1_000;

    // 0x3FFFFFFFF is max 34-bit unsigned integer
    if (sec >= 0 && sec <= 0x3FFFFFFFF) {
      // Timestamp 32 — 1970..2106, no nanoseconds
      if (nano == 0 && sec <= limitUint32) {
        wr
          ..writeUint8(fFixExt4)
          ..writeInt8(extTypeTimestamp)
          ..writeUint32(sec);
        return;
      }

      // Timestamp 64 — 1970..~2514, with nanoseconds.
      //
      // IMPORTANT: MessagePack TS64 format stores nanoseconds in the upper
      // 30 bits and seconds in the lower 34 bits of an 8-byte unsigned integer.
      //
      // Dart's bitwise operators work on 64-bit integers on native platforms
      // but are restricted to 32 bits on Web (Dart2JS).
      // To ensure cross-platform correctness, we split the 64-bit payload
      // into two 32-bit writes.
      final high32 = (nano << 2) | (sec ~/ 0x100000000);
      final low32 = sec & 0xFFFFFFFF;

      wr
        ..writeUint8(fFixExt8)
        ..writeInt8(extTypeTimestamp)
        ..writeUint32(high32)
        ..writeUint32(low32);
    } else {
      // Timestamp 96 — before 1970 or after ~2514
      wr
        ..writeUint8(fExt8)
        ..writeUint8(12)
        ..writeInt8(extTypeTimestamp)
        ..writeUint32(nano)
        ..writeInt64(sec);
    }
  }

  /// Decodes a timestamp payload of [length] bytes from [rd] (the ext marker
  /// and type byte have already been consumed by the caller).
  static DateTime decode(BinaryReader rd, int length) {
    switch (length) {
      case 4:
        final seconds = rd.readUint32();
        return DateTime.fromMillisecondsSinceEpoch(
          seconds * 1000,
          isUtc: true,
        );
      case 8:
        final data64 = rd.readUint64();
        // TS64 format: 30 bits for nanoseconds, 34 bits for seconds.
        // nanoSeconds = data64 >> 34
        // seconds = data64 & 0x3FFFFFFFF (34 bits mask)
        final nanoSeconds = (data64 >> 34) & 0x3FFFFFFF;
        final seconds = data64 & 0x3FFFFFFFF;
        final microseconds = seconds * 1000000 + nanoSeconds ~/ 1000;
        return DateTime.fromMicrosecondsSinceEpoch(
          microseconds,
          isUtc: true,
        );
      case 12:
        final nanoSeconds = rd.readUint32();
        final seconds = rd.readInt64();
        final microseconds = seconds * 1000000 + nanoSeconds ~/ 1000;
        return DateTime.fromMicrosecondsSinceEpoch(
          microseconds,
          isUtc: true,
        );
      default:
        throw MessagePackFormatException(
          'Invalid timestamp length: $length',
          'Timestamps must be 4, 8, or 12 bytes long according to the spec.',
        );
    }
  }
}

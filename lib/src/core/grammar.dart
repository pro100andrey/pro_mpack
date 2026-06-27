/// One home for the MessagePack wire-format grammar.
///
/// This describes, per header byte, the *shape* of the value that follows:
/// which structural category it is and how a skip-walk advances past it. It is
/// the single source of truth shared by the two skip-walkers —
/// `MessagePackScanner` (streaming reader) and `Unpacker.skip()` (complete
/// buffer reader) — so the streaming-skip path cannot drift from the
/// buffered-skip path, and no third copy of the framing rules is introduced.
///
/// The materializing `Unpacker.unpack()` keeps its own hot-path switch: it is
/// the performance-critical decode path and is not a skip-walk, so it is
/// deliberately not routed through this table.
///
/// `MpShape`, `mpShapes`, and `mpFixedSkip` are public-named so both readers
/// can consult the table, but they are not exported from `pro_mpack.dart` and
/// are not part of the public API.
library;

import 'constants.dart';

/// Structural category of a MessagePack value, keyed by its header byte.
///
/// A skip-walker reads the header, looks up [mpShapes], and dispatches on the
/// shape — reading any length prefix and advancing the reader accordingly.
enum MpShape {
  /// The header byte fully encodes the value; nothing follows
  /// (`nil`, `true`, `false`, positive/negative fixint).
  single,

  /// A fixed number of payload bytes follow; the count is [mpFixedSkip].
  /// (`float32/64`, `uint8..64`, `int8..64`).
  fixed,

  /// `fixstr`: the byte length is in the header's low 5 bits.
  fixStr,

  /// `fixarray`: the element count is in the header's low 4 bits.
  fixArray,

  /// `fixmap`: the entry count is in the header's low 4 bits (×2 values).
  fixMap,

  /// `str8`/`bin8`: 1 length byte, then that many data bytes.
  strBin8,

  /// `str16`/`bin16`: 2 length bytes, then that many data bytes.
  strBin16,

  /// `str32`/`bin32`: 4 length bytes, then that many data bytes.
  strBin32,

  /// `array16`: 2 count bytes, then that many elements.
  array16,

  /// `array32`: 4 count bytes, then that many elements.
  array32,

  /// `map16`: 2 count bytes, then that many entries (×2 values).
  map16,

  /// `map32`: 4 count bytes, then that many entries (×2 values).
  map32,

  /// `fixext1..16`: 1 type byte, then [mpFixedSkip] data bytes.
  fixExt,

  /// `ext8`: 1 length byte, then 1 type byte + that many data bytes.
  ext8,

  /// `ext16`: 2 length bytes, then 1 type byte + that many data bytes.
  ext16,

  /// `ext32`: 4 length bytes, then 1 type byte + that many data bytes.
  ext32,

  /// `0xc1` — reserved by the spec, never valid.
  neverUsed,

  /// Not a known MessagePack header byte.
  unknown,
}

/// Shape of every header byte (0..255). Built once at load.
final List<MpShape> mpShapes = _buildShapes();

/// For [MpShape.fixed] and [MpShape.fixExt] header bytes, the number of fixed
/// payload (data) bytes. `0` for all other bytes. The `fixExt` type byte is not
/// counted here — the walker adds it.
final List<int> mpFixedSkip = _buildFixedSkip();

List<MpShape> _buildShapes() {
  final t = List<MpShape>.filled(256, MpShape.unknown);

  // Positive fixint 0x00..0x7f and negative fixint 0xe0..0xff.
  for (var b = 0; b <= limitInt8; b++) {
    t[b] = MpShape.single;
  }
  for (var b = fNegFixIntPrefix; b <= 0xff; b++) {
    t[b] = MpShape.single;
  }

  t[fNil] = MpShape.single;
  t[fFalse] = MpShape.single;
  t[fTrue] = MpShape.single;

  t[fFloat32] = MpShape.fixed;
  t[fFloat64] = MpShape.fixed;
  t[fUint8] = MpShape.fixed;
  t[fUint16] = MpShape.fixed;
  t[fUint32] = MpShape.fixed;
  t[fUint64] = MpShape.fixed;
  t[fInt8] = MpShape.fixed;
  t[fInt16] = MpShape.fixed;
  t[fInt32] = MpShape.fixed;
  t[fInt64] = MpShape.fixed;

  // fixstr 0xa0..0xbf.
  for (var b = fFixStrPrefix; b <= fFixStrEnd; b++) {
    t[b] = MpShape.fixStr;
  }
  t[fStr8] = MpShape.strBin8;
  t[fStr16] = MpShape.strBin16;
  t[fStr32] = MpShape.strBin32;
  t[fBin8] = MpShape.strBin8;
  t[fBin16] = MpShape.strBin16;
  t[fBin32] = MpShape.strBin32;

  // fixarray 0x90..0x9f.
  for (var b = fFixArrayPrefix; b <= fFixArrayEnd; b++) {
    t[b] = MpShape.fixArray;
  }
  t[fArray16] = MpShape.array16;
  t[fArray32] = MpShape.array32;

  // fixmap 0x80..0x8f.
  for (var b = fFixMapPrefix; b <= fFixMapEnd; b++) {
    t[b] = MpShape.fixMap;
  }
  t[fMap16] = MpShape.map16;
  t[fMap32] = MpShape.map32;

  t[fFixExt1] = MpShape.fixExt;
  t[fFixExt2] = MpShape.fixExt;
  t[fFixExt4] = MpShape.fixExt;
  t[fFixExt8] = MpShape.fixExt;
  t[fFixExt16] = MpShape.fixExt;
  t[fExt8] = MpShape.ext8;
  t[fExt16] = MpShape.ext16;
  t[fExt32] = MpShape.ext32;

  t[fNeverUsed] = MpShape.neverUsed;

  return t;
}

List<int> _buildFixedSkip() {
  final t = List<int>.filled(256, 0);

  t[fFloat32] = 4;
  t[fFloat64] = 8;
  t[fUint8] = 1;
  t[fUint16] = 2;
  t[fUint32] = 4;
  t[fUint64] = 8;
  t[fInt8] = 1;
  t[fInt16] = 2;
  t[fInt32] = 4;
  t[fInt64] = 8;

  t[fFixExt1] = 1;
  t[fFixExt2] = 2;
  t[fFixExt4] = 4;
  t[fFixExt8] = 8;
  t[fFixExt16] = 16;

  return t;
}

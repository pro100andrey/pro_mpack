/// MessagePack format constants and definitions.
///
/// This library defines all the format type codes and value limits
/// specified in the MessagePack specification. These constants are used
/// internally by the serializer and deserializer to identify and encode
/// different data types.
///
/// The MessagePack format uses a type-byte prefix to identify the type
/// and often the length of the data that follows. For example:
/// - 0x00-0x7f: positive fixint (single-byte positive integers)
/// - 0xe0-0xff: negative fixint (single-byte negative integers)
/// - 0xa0-0xbf: fixstr (short strings with length in lower 5 bits)
/// - 0x90-0x9f: fixarray (short arrays with length in lower 4 bits)
/// - 0x80-0x8f: fixmap (short maps with length in lower 4 bits)
///
/// For detailed format specifications, see:
/// https://github.com/msgpack/msgpack/blob/master/spec.md#formats-overview
library;

// Nil format

/// Format byte for `nil`.
const fNil = 0xc0; // 192, nil

// Never used (reserved by MessagePack specification)

/// Format byte reserved by the specification and never used.
const fNeverUsed = 0xc1; // 193, never used

// Boolean formats

/// Format byte for `false`.
const fFalse = 0xc2; // 194, false
/// Format byte for `true`.
const fTrue = 0xc3; // 195, true

// Binary formats

/// Format byte for binary data (length up to 255 bytes).
const fBin8 = 0xc4; // 196
/// Format byte for binary data (length up to 65535 bytes).
const fBin16 = 0xc5; // 197
/// Format byte for binary data (length up to 4GB).
const fBin32 = 0xc6; // 198

// Extension formats

/// Format byte for variable-length extensions (length up to 255 bytes).
const fExt8 = 0xc7; // 199
/// Format byte for variable-length extensions (length up to 65535 bytes).
const fExt16 = 0xc8; // 200
/// Format byte for variable-length extensions (length up to 4GB).
const fExt32 = 0xc9; // 201

// Float formats

/// Format byte for 32-bit floating point numbers.
const fFloat32 = 0xca; // 202
/// Format byte for 64-bit floating point numbers.
const fFloat64 = 0xcb; // 203

// Integer formats

/// Format byte for 8-bit unsigned integers.
const fUint8 = 0xcc; // 204
/// Format byte for 16-bit unsigned integers.
const fUint16 = 0xcd; // 205
/// Format byte for 32-bit unsigned integers.
const fUint32 = 0xce; // 206
/// Format byte for 64-bit unsigned integers.
const fUint64 = 0xcf; // 207

/// Format byte for 8-bit signed integers.
const fInt8 = 0xd0; // 208
/// Format byte for 16-bit signed integers.
const fInt16 = 0xd1; // 209
/// Format byte for 32-bit signed integers.
const fInt32 = 0xd2; // 210
/// Format byte for 64-bit signed integers.
const fInt64 = 0xd3; // 211

// Fixed-length Extension formats

/// Format byte for extensions with exactly 1 byte of payload.
const fFixExt1 = 0xd4; // 212
/// Format byte for extensions with exactly 2 bytes of payload.
const fFixExt2 = 0xd5; // 213
/// Format byte for extensions with exactly 4 bytes of payload.
const fFixExt4 = 0xd6; // 214
/// Format byte for extensions with exactly 8 bytes of payload.
const fFixExt8 = 0xd7; // 215
/// Format byte for extensions with exactly 16 bytes of payload.
const fFixExt16 = 0xd8; // 216

// String formats

/// Format byte for strings (length up to 255 bytes).
const fStr8 = 0xd9; // 217
/// Format byte for strings (length up to 65535 bytes).
const fStr16 = 0xda; // 218
/// Format byte for strings (length up to 4GB).
const fStr32 = 0xdb; // 219

// Array formats

/// Format byte for arrays (length up to 65535 elements).
const fArray16 = 0xdc; // 220
/// Format byte for arrays (length up to 4GB elements).
const fArray32 = 0xdd; // 221

// Map formats

/// Format byte for maps (length up to 65535 entries).
const fMap16 = 0xde; // 222
/// Format byte for maps (length up to 4GB entries).
const fMap32 = 0xdf; // 223

// Fix formats masks and ranges

/// Prefix for negative fixint (-32 to -1).
const fNegFixIntPrefix = 0xe0; // 224
/// Prefix for fixmap (0 to 15 entries).
const fFixMapPrefix = 0x80; // 128
/// End of fixmap range.
const fFixMapEnd = 0x8f; // 143
/// Prefix for fixarray (0 to 15 elements).
const fFixArrayPrefix = 0x90; // 144
/// End of fixarray range.
const fFixArrayEnd = 0x9f; // 159
/// Prefix for fixstr (0 to 31 bytes).
const fFixStrPrefix = 0xa0; // 160
/// End of fixstr range.
const fFixStrEnd = 0xbf; // 191
/// Mask for extract data from fixstr header.
const fFixStrDataMask = 0x1f; // 31
/// Mask for extract count from fixarray/fixmap header.
const fFixCountMask = 0x0f;

// Value limits

/// Maximum value for positive fixint.
const limitInt8 = 0x7f; // 127
/// Maximum value for uint8.
const limitUint8 = 0xff; // 255
/// Maximum value for uint32.
const limitUint32 = 0xffffffff; // 4294967295
/// Maximum value for uint16.
const limitUint16 = 0xffff; // 65535
/// Minimum value for negative fixint.
const limitNegFixInt = -0x20; // -32
/// Minimum value for int8.
const limitNegInt8 = -0x80; // -128
/// Minimum value for int16.
const limitNegInt16 = -0x8000; // -32768
/// Minimum value for int32.
const limitNegInt32 = -0x80000000; // -2147483648

// Extension types

/// Standard extension type ID for timestamps.
const extTypeTimestamp = -1;

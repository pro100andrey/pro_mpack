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
const fNil = 0xc0; // 192, nil

// Never used (reserved by MessagePack specification)
const fNeverUsed = 0xc1; // 193, never used

// Boolean formats
const fFalse = 0xc2; // 194, false
const fTrue = 0xc3; // 195, true

// Binary formats
const fBin8 = 0xc4; // 196
const fBin16 = 0xc5; // 197
const fBin32 = 0xc6; // 198

// Extension formats
const fExt8 = 0xc7; // 199
const fExt16 = 0xc8; // 200
const fExt32 = 0xc9; // 201

// Float formats
const fFloat32 = 0xca; // 202
const fFloat64 = 0xcb; // 203

// Integer formats
const fUint8 = 0xcc; // 204
const fUint16 = 0xcd; // 205
const fUint32 = 0xce; // 206
const fUint64 = 0xcf; // 207

const fInt8 = 0xd0; // 208
const fInt16 = 0xd1; // 209
const fInt32 = 0xd2; // 210
const fInt64 = 0xd3; // 211

// Extension formats
const fFixExt1 = 0xd4; // 212
const fFixExt2 = 0xd5; // 213
const fFixExt4 = 0xd6; // 214
const fFixExt8 = 0xd7; // 215
const fFixExt16 = 0xd8; // 216

// String formats
const fStr8 = 0xd9; // 217
const fStr16 = 0xda; // 218
const fStr32 = 0xdb; // 219

// Array formats
const fArray16 = 0xdc; // 220
const fArray32 = 0xdd; // 221

// Map formats
const fMap16 = 0xde; // 222
const fMap32 = 0xdf; // 223

// Fix formats masks and ranges
const fNegFixIntPrefix = 0xe0; // 224
const fFixMapPrefix = 0x80; // 128
const fFixMapEnd = 0x8f; // 143
const fFixArrayPrefix = 0x90; // 144
const fFixArrayEnd = 0x9f; // 159
const fFixStrPrefix = 0xa0; // 160
const fFixStrEnd = 0xbf; // 191
const fFixStrDataMask = 0x1f; // 31
const fFixCountMask = 0x0f;

// Value limits
const limitInt8 = 0x7f; // 127
const limitUint8 = 0xff; // 255
const limitUint32 = 0xffffffff; // 4294967295
const limitUint16 = 0xffff; // 65535
const limitNegFixInt = -0x20; // -32
const limitNegInt8 = -0x80; // -128
const limitNegInt16 = -0x8000; // -32768
const limitNegInt32 = -0x80000000; // -2147483648

// Extension types
const extTypeTimestamp = -1;

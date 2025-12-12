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
const formatNil = 0xc0;

// Boolean formats
const formatFalse = 0xc2;
const formatTrue = 0xc3;

// Integer formats
const formatUint8 = 0xcc;
const formatUint16 = 0xcd;
const formatUint32 = 0xce;
const formatUint64 = 0xcf;

const formatInt8 = 0xd0;
const formatInt16 = 0xd1;
const formatInt32 = 0xd2;
const formatInt64 = 0xd3;

// Float formats
const formatFloat32 = 0xca;
const formatFloat64 = 0xcb;

// String formats
const formatStr8 = 0xd9;
const formatStr16 = 0xda;
const formatStr32 = 0xdb;

// Binary formats
const formatBin8 = 0xc4;
const formatBin16 = 0xc5;
const formatBin32 = 0xc6;

// Array formats
const formatArray16 = 0xdc;
const formatArray32 = 0xdd;

// Map formats
const formatMap16 = 0xde;
const formatMap32 = 0xdf;

// Extension formats
const formatFixExt1 = 0xd4;
const formatFixExt2 = 0xd5;
const formatFixExt4 = 0xd6;
const formatFixExt8 = 0xd7;
const formatFixExt16 = 0xd8;

const formatExt8 = 0xc7;
const formatExt16 = 0xc8;
const formatExt32 = 0xc9;

// Fix formats masks and ranges
const formatPosFixIntMask = 0x80; // 0xxxxxxx
const formatNegFixIntMask = 0xe0; // 111xxxxx
const formatNegFixIntPrefix = 0xe0;
const formatFixMapMask = 0xf0; // 1000xxxx
const formatFixMapPrefix = 0x80;
const formatFixArrayMask = 0xf0; // 1001xxxx
const formatFixArrayPrefix = 0x90;
const formatFixStrMask = 0xe0; // 101xxxxx
const formatFixStrPrefix = 0xa0;

// Value limits
const limitUint32 = 4294967295; // 0xFFFFFFFF
const limitUint16 = 65535; // 0xFFFF
const limitUint8 = 255; // 0xFF

const limitInt32 = 2147483647;
const limitInt16 = 32767;
const limitInt8 = 127;
const limitNegativeInt5 = -32;
const limitNegativeInt8 = -128;
const limitNegativeInt16 = -32768;
const limitNegativeInt32 = -2147483648;

// Extension types
const extTypeTimestamp = -1;

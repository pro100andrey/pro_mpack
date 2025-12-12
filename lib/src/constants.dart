/// MessagePack format constants.
///
/// See https://github.com/msgpack/msgpack/blob/master/spec.md#formats-overview

// Nil format
const int formatNil = 0xc0;

// Boolean formats
const int formatFalse = 0xc2;
const int formatTrue = 0xc3;

// Integer formats
const int formatUint8 = 0xcc;
const int formatUint16 = 0xcd;
const int formatUint32 = 0xce;
const int formatUint64 = 0xcf;

const int formatInt8 = 0xd0;
const int formatInt16 = 0xd1;
const int formatInt32 = 0xd2;
const int formatInt64 = 0xd3;

// Float formats
const int formatFloat32 = 0xca;
const int formatFloat64 = 0xcb;

// String formats
const int formatStr8 = 0xd9;
const int formatStr16 = 0xda;
const int formatStr32 = 0xdb;

// Binary formats
const int formatBin8 = 0xc4;
const int formatBin16 = 0xc5;
const int formatBin32 = 0xc6;

// Array formats
const int formatArray16 = 0xdc;
const int formatArray32 = 0xdd;

// Map formats
const int formatMap16 = 0xde;
const int formatMap32 = 0xdf;

// Extension formats
const int formatFixExt1 = 0xd4;
const int formatFixExt2 = 0xd5;
const int formatFixExt4 = 0xd6;
const int formatFixExt8 = 0xd7;
const int formatFixExt16 = 0xd8;

const int formatExt8 = 0xc7;
const int formatExt16 = 0xc8;
const int formatExt32 = 0xc9;

// Fix formats masks and ranges
const int formatPosFixIntMask = 0x80; // 0xxxxxxx
const int formatNegFixIntMask = 0xe0; // 111xxxxx
const int formatNegFixIntPrefix = 0xe0;
const int formatFixMapMask = 0xf0; // 1000xxxx
const int formatFixMapPrefix = 0x80;
const int formatFixArrayMask = 0xf0; // 1001xxxx
const int formatFixArrayPrefix = 0x90;
const int formatFixStrMask = 0xe0; // 101xxxxx
const int formatFixStrPrefix = 0xa0;

// Value limits
const int limitUint32 = 4294967295; // 0xFFFFFFFF
const int limitUint16 = 65535; // 0xFFFF
const int limitUint8 = 255; // 0xFF

const int limitInt32 = 2147483647;
const int limitInt16 = 32767;
const int limitInt8 = 127;
const int limitNegativeInt5 = -32;
const int limitNegativeInt8 = -128;
const int limitNegativeInt16 = -32768;
const int limitNegativeInt32 = -2147483648;

// Extension types
const int extTypeTimestamp = -1;

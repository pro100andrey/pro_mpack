import 'dart:typed_data';

import 'package:pro_mpack/pro_mpack.dart';

class CustomExtension {
  CustomExtension(this.type, this.data);
  final int type;
  final Uint8List data;
}

DecodeExt createCustomDecoder() =>
    (extType, length, unpacker) =>
        'Custom ext type $extType with data ${unpacker.readBytes(length)}';

EncodeExt createCustomEncoder() => (value, packer) {
  if (value is CustomExtension) {
    packer.packExt(value.type, (p) {
      p.appendRaw(value.data);
    });
    return true;
  }
  return false;
};

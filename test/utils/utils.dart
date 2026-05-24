import 'dart:typed_data';

import 'package:pro_mpack/pro_mpack.dart';

class CustomExtension {
  CustomExtension(this.type, this.data);
  final int type;
  final Uint8List data;
}

DecodeExt createCustomDecoder() {
  return (int extType, Uint8List data) =>
      'Custom ext type $extType with data $data';
}

EncodeExt createCustomEncoder() {
  return (Object value) {
    if (value is CustomExtension) {
      return (type: value.type, data: value.data);
    }
    return null;
  };
}

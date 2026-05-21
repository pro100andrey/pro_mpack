import 'dart:typed_data';

import 'package:pro_mpack/pro_mpack.dart';

class CustomExtDecoder with ExtDecoder {
  @override
  Object? decodeObject(int extType, Uint8List data) =>
      'Custom ext type $extType with data $data';
}

class CustomExtension {
  CustomExtension(this.type, this.data);
  final int type;
  final Uint8List data;
}

class TestExtEncoder with ExtEncoder {
  @override
  int? extTypeForObject(Object? object) {
    if (object is CustomExtension) {
      return object.type;
    }
    return null;
  }

  @override
  Uint8List encodeObject(Object? object) {
    if (object is CustomExtension) {
      return object.data;
    }

    throw Exception('Unknown object type');
  }
}

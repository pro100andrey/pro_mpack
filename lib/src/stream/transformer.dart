import 'dart:async';

import 'package:pro_binary/pro_binary.dart';

import '../message_pack.dart';
import 'scanner.dart';

/// A [StreamTransformer] that decodes a stream of MessagePack bytes
/// into a stream of Dart objects.
///
/// It uses a zero-allocation [MessagePackScanner] to validate the exact length
/// of incoming messages before passing them to the optimized [MessagePack]
/// unpacker. This avoids garbage collection overhead from partially decoded
/// messages when chunk boundaries split large objects.
class MessagePackStreamTransformer
    extends StreamTransformerBase<List<int>, dynamic> {
  /// Creates a new [MessagePackStreamTransformer] using the provided codec.
  const MessagePackStreamTransformer(this._mp);

  final MessagePack _mp;

  @override
  Stream<dynamic> bind(Stream<List<int>> stream) async* {
    final reader = StreamBinaryReader();

    await for (final chunk in stream) {
      reader.addChunk(chunk);

      while (reader.availableBytes > 0) {
        reader.bookmark();
        final bytesBefore = reader.availableBytes;

        try {
          // Use the scanner to quickly validate and find the exact byte size
          // of the next message.
          MessagePackScanner.skip(reader);
          final consumed = bytesBefore - reader.availableBytes;

          // Rollback so we can read the exact full payload
          reader.rollback();

          // Read the exact payload and decode it optimally
          final payload = reader.readBytes(consumed);
          yield _mp.unpack<dynamic>(payload);
        } on NotEnoughDataException {
          // The message is incomplete. Rollback and wait for the next chunk.
          reader.rollback();
          break;
        } catch (e) {
          // In case of parsing errors, rollback to clean up state
          reader.rollback();
          rethrow;
        }
      }
    }
  }
}

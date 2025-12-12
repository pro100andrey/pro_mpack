/// Error thrown when a MessagePack operation fails.
class MessagePackError extends Error {
  /// Creates a [MessagePackError] with an optional [message].
  MessagePackError([this.message]);

  /// The error message.
  final String? message;

  @override
  String toString() {
    if (message != null) {
      return 'MessagePackError: $message';
    }
    return 'MessagePackError';
  }
}

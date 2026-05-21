/// Error thrown when a MessagePack serialization or deserialization
/// operation fails.
///
/// This error is thrown in various scenarios:
/// - Invalid MessagePack format encountered during deserialization
/// - Data structures exceeding MessagePack size limits
/// - Unsupported types during serialization
/// - Invalid extension type codes
/// - Insufficient buffer data during deserialization
///
/// Example:
/// ```dart
/// try {
///   final data = deserialize(invalidBytes);
/// } on MessagePackError catch (e) {
///   print('Failed to deserialize: ${e.message}');
/// }
/// ```
class MessagePackError extends Error {
  /// Creates a [MessagePackError] with an optional [message].
  ///
  /// [message]: A description of what went wrong during the operation.
  MessagePackError(this.message);

  /// The error message.
  final String message;

  @override
  String toString() => 'MessagePackError: $message';
}

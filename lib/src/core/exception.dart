/// Exception thrown when a MessagePack serialization or deserialization
/// operation fails.
///
/// This exception is thrown in various scenarios:
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
/// } on MessagePackException catch (e) {
///   print('Failed to deserialize: ${e.message}');
/// }
/// ```
class MessagePackException implements Exception {
  /// Creates a [MessagePackException] with an optional [message].
  ///
  /// [message]: A description of what went wrong during the operation.
  MessagePackException(this.message);

  /// The exception message.
  final String message;

  @override
  String toString() => 'MessagePackException: $message';
}

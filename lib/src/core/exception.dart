/// Base class for all exceptions thrown by the MessagePack library.
///
/// This is a `sealed` class, meaning you can exhaustively catch all its
/// subclasses in a `switch` statement to handle different error scenarios
/// gracefully.
///
/// Example:
/// ```dart
/// try {
///   final data = deserialize(bytes);
/// } on MessagePackException catch (e) {
///   switch (e) {
///     case MessagePackFormatException():
///       print('Data is corrupted: ${e.message}');
///     case MessagePackUnsupportedTypeException():
///       print('Tried to encode unknown type: ${e.unsupportedType}');
///     case MessagePackSizeException():
///       print('Payload too large: ${e.message}');
///     case MessagePackConfigurationException():
///       print('Extension config error: ${e.message}');
///   }
/// }
/// ```
sealed class MessagePackException implements Exception {
  /// Creates a [MessagePackException].
  const MessagePackException(this.message, [this.suggestion]);

  /// The description of what went wrong.
  final String message;

  /// An optional actionable suggestion on how to fix the error.
  final String? suggestion;

  /// The name of the exception, used in [toString].
  String get name;

  @override
  String toString() {
    final buffer = StringBuffer('$name: $message');
    if (suggestion != null) {
      buffer.write('\nSuggestion: $suggestion');
    }
    return buffer.toString();
  }
}

/// Thrown when the binary data does not conform to the MessagePack spec.
///
/// Examples include encountering reserved bytes (0xc1), malformed timestamps,
/// or reaching the end of the buffer unexpectedly.
class MessagePackFormatException extends MessagePackException {
  /// Creates a [MessagePackFormatException].
  const MessagePackFormatException(super.message, [super.suggestion]);

  @override
  String get name => 'MessagePackFormatException';
}

/// Thrown when attempting to serialize an object that isn't supported.
///
/// This happens when an object is not a primitive type, not a collection,
/// and has no registered custom extension encoder.
class MessagePackUnsupportedTypeException extends MessagePackException {
  /// Creates a [MessagePackUnsupportedTypeException].
  const MessagePackUnsupportedTypeException(
    this.unsupportedType,
    super.message, [
    super.suggestion,
  ]);

  /// The runtime type of the object that caused the serialization failure.
  final Type unsupportedType;

  @override
  String get name => 'MessagePackUnsupportedTypeException';
}

/// Thrown when a string, collection, or binary blob exceeds MessagePack limits.
///
/// MessagePack specifies a maximum size of 2^32 - 1 (approx 4GB) for elements.
class MessagePackSizeException extends MessagePackException {
  /// Creates a [MessagePackSizeException].
  const MessagePackSizeException(super.message, [super.suggestion]);

  @override
  String get name => 'MessagePackSizeException';
}

/// Thrown when there's an error in the custom extension configuration.
///
/// Examples include registering duplicate extension IDs, using out-of-range
/// IDs (-128 to 127), or missing decoders.
class MessagePackConfigurationException extends MessagePackException {
  /// Creates a [MessagePackConfigurationException].
  const MessagePackConfigurationException(super.message, [super.suggestion]);

  @override
  String get name => 'MessagePackConfigurationException';
}

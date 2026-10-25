/// Base exception class for all StudyGemma domain and data layer errors.
class AppException implements Exception {
  const AppException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => cause == null
      ? '$runtimeType: $message'
      : '$runtimeType: $message ($cause)';
}

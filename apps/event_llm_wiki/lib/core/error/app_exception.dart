/// Base type for all typed failures surfaced by the data/domain layers.
///
/// Repositories and services MUST throw a subtype of [AppException] instead
/// of letting platform exceptions (e.g. `PlatformException`, raw
/// `flutter_litert_lm` engine errors, `http` socket errors) escape uncaught.
/// This keeps failure handling in the UI layer exhaustive and testable
/// without a real device, a real 529MB model, or a real network call.
///
/// Same contract as `apps/rps_live/lib/core/error/app_exception.dart` — kept
/// identical across apps in this repo so `flutter-reviewer` can apply one
/// shared compliance rule everywhere.
abstract class AppException implements Exception {
  const AppException(this.message, {this.cause});

  final String message;

  /// The original error that triggered this exception, if any (useful for
  /// logging without leaking platform-specific types into the UI layer).
  final Object? cause;

  @override
  String toString() => '$runtimeType: $message';
}

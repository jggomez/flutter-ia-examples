import '../../core/error/app_exception.dart';
import '../models/talk.dart';

/// Read-only access to the bundled conference agenda
/// (`assets/agenda.json`).
///
/// The real implementation (`data/repositories/agenda_repository_impl.dart`)
/// parses the asset once via `AgendaAssetService` and caches the resulting
/// `List<Talk>` in memory for the rest of the app session — the agenda is
/// bundled, read-only content, never written to or re-fetched (see
/// PLAN.md's non-goals: no in-app agenda editing/sync). Tests inject a
/// `FakeAgendaRepository` backed by an in-memory list, so
/// `RetrieveRelevantTalksUseCase`/view-model tests never touch
/// `rootBundle`.
abstract class AgendaRepository {
  /// All talks in the bundled agenda, in no particular guaranteed order
  /// (callers that need chronological order should sort by
  /// `Talk.startTime`).
  ///
  /// Throws [AgendaLoadException] if `assets/agenda.json` is missing,
  /// unreadable, or fails schema parsing — this should never happen with a
  /// correctly bundled asset, but must not surface as an unhandled parse
  /// error.
  Future<List<Talk>> getAllTalks();

  /// A single talk by [id], for `TalkDetailViewModel` and for resolving a
  /// citation chip tap back to its full [Talk].
  ///
  /// Throws [TalkNotFoundException] if no talk with [id] exists.
  Future<Talk> getTalkById(String id);
}

/// Thrown when `assets/agenda.json` cannot be loaded or parsed.
class AgendaLoadException extends AppException {
  const AgendaLoadException(super.message, {super.cause});
}

/// Thrown by [AgendaRepository.getTalkById] when [id] does not match any
/// talk in the bundled agenda.
class TalkNotFoundException extends AppException {
  const TalkNotFoundException(super.message, {super.cause});
}

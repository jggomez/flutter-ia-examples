import 'conference_day.dart';
import 'conference_track.dart';
import 'speaker.dart';

/// A single agenda entry: one talk, at one time slot, on one track, on one
/// day, given by one or more [speakers].
///
/// This is the unit [RetrieveRelevantTalksUseCase] scores and returns, and
/// the unit `AgendaAssetService`/`AgendaRepositoryImpl` parse
/// `assets/agenda.json` into. Field weights used by the lexical RAG scorer
/// (see `doc/adr/0002-rag-lexical-retrieval.md`) are: [title] x3,
/// [speakers] names x2, [track]/[day] x1, [abstract] x1.
class Talk {
  const Talk({
    required this.id,
    required this.title,
    required this.abstract,
    required this.speakers,
    required this.day,
    required this.track,
    required this.startTime,
    required this.durationMinutes,
  });

  /// Stable identifier, e.g. `'talk-001'`. Used as the Hive-persisted
  /// citation key (`ChatMessageDto.citedTalkIds`) and as the final,
  /// deterministic tie-break in the RAG scorer's sort order.
  final String id;

  final String title;

  final String abstract;

  final List<Speaker> speakers;

  final ConferenceDay day;

  final ConferenceTrack track;

  /// Session start time. Used both for chronological display on the Agenda
  /// tab and as a tie-break in the RAG scorer's sort order.
  final DateTime startTime;

  final int durationMinutes;
}

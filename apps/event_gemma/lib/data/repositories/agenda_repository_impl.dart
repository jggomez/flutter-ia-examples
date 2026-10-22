// A leading underscore in a named-constructor-parameter name makes it
// library-private, which would break `main.dart`'s (a different library)
// ability to pass it by name — so the field below is assigned manually in
// the initializer list instead of via an initializing formal. See
// `apps/rps_live/lib/data/repositories/classifier_repository_impl.dart` for
// the identical convention this mirrors.
// ignore_for_file: prefer_initializing_formals

import 'dart:convert';

import '../../domain/models/conference_day.dart';
import '../../domain/models/conference_track.dart';
import '../../domain/models/speaker.dart';
import '../../domain/models/talk.dart';
import '../../domain/repositories/agenda_repository.dart';
import '../services/agenda_asset_service.dart';

/// [AgendaRepository] backed by [AgendaAssetService].
///
/// Parses `assets/agenda.json` once and caches the resulting `List<Talk>`
/// in memory for the rest of the app session (the agenda is bundled,
/// read-only content — see the interface's doc comment). Both
/// [getAllTalks] and [getTalkById] read from that cache; only the very
/// first call does any I/O/parsing.
class AgendaRepositoryImpl implements AgendaRepository {
  AgendaRepositoryImpl({required AgendaAssetService agendaAssetService})
    : _agendaAssetService = agendaAssetService;

  final AgendaAssetService _agendaAssetService;

  List<Talk>? _cachedTalks;

  @override
  Future<List<Talk>> getAllTalks() async {
    final cached = _cachedTalks;
    if (cached != null) return cached;

    try {
      final json = await _agendaAssetService.loadAgendaJson();
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      final rawTalks = decoded['talks'] as List<dynamic>;
      final talks = rawTalks
          .map((raw) => _talkFromJson(raw as Map<String, dynamic>))
          .toList(growable: false);
      _cachedTalks = talks;
      return talks;
    } on AgendaLoadException {
      rethrow;
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(
        AgendaLoadException(
          'Failed to load or parse assets/agenda.json.',
          cause: error,
        ),
        stackTrace,
      );
    }
  }

  @override
  Future<Talk> getTalkById(String id) async {
    final talks = await getAllTalks();
    for (final talk in talks) {
      if (talk.id == id) return talk;
    }
    throw TalkNotFoundException('No talk with id "$id" in the agenda.');
  }

  Talk _talkFromJson(Map<String, dynamic> json) {
    final rawSpeakers = json['speakers'] as List<dynamic>;
    return Talk(
      id: json['id'] as String,
      title: json['title'] as String,
      abstract: json['abstract'] as String,
      speakers: rawSpeakers
          .map((raw) => _speakerFromJson(raw as Map<String, dynamic>))
          .toList(growable: false),
      day: ConferenceDay.values.byName(json['day'] as String),
      track: ConferenceTrack.values.byName(json['track'] as String),
      startTime: DateTime.parse(json['startTime'] as String),
      durationMinutes: json['durationMinutes'] as int,
    );
  }

  Speaker _speakerFromJson(Map<String, dynamic> json) => Speaker(
    name: json['name'] as String,
    title: json['title'] as String,
    company: json['company'] as String?,
  );
}

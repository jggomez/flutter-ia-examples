/// One of the two days of the conference this app's bundled agenda covers.
///
/// Kept as an enum (mirrors `apps/rps_live`'s `Move`/`RoundOutcome` style)
/// rather than a free-form `DateTime`-only field, so the Agenda tab can
/// group/filter talks by day without re-deriving a day identity from a
/// timestamp.
enum ConferenceDay { dayOne, dayTwo }

/// Display metadata for a [ConferenceDay]. Kept as an extension (not fields
/// on the enum itself) so `assets/agenda.json`'s actual calendar dates can
/// change without touching the domain enum.
extension ConferenceDayX on ConferenceDay {
  String get label => switch (this) {
    ConferenceDay.dayOne => 'Day 1',
    ConferenceDay.dayTwo => 'Day 2',
  };
}

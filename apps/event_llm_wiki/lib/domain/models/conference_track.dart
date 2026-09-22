/// One of the two parallel tracks talks in the bundled agenda run in.
enum ConferenceTrack { engineering, productAndDesign }

/// Display metadata for a [ConferenceTrack]. See [ConferenceDayX] for why
/// this is an extension rather than enum fields.
extension ConferenceTrackX on ConferenceTrack {
  String get label => switch (this) {
    ConferenceTrack.engineering => 'Engineering',
    ConferenceTrack.productAndDesign => 'Product & Design',
  };
}

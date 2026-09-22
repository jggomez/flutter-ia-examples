/// A conference speaker, as referenced by one or more [Talk]s.
///
/// Kept minimal on purpose (see PLAN.md non-goals — no speaker photos, no
/// bookmarking). Speakers are embedded inline in `assets/agenda.json`
/// per-talk rather than normalized into their own top-level collection: the
/// bundled agenda is small and read-only, so there is no update-anomaly risk
/// that would justify the extra indirection.
class Speaker {
  const Speaker({required this.name, required this.title, this.company});

  /// Full display name, e.g. "Ada Lovelace".
  final String name;

  /// Role/title, e.g. "Principal Engineer".
  final String title;

  /// Optional company/affiliation, e.g. "Acme Corp". Null when not
  /// applicable (e.g. independent/academic speakers).
  final String? company;
}

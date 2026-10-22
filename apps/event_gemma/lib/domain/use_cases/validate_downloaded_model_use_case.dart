/// Sanity-checks a downloaded `.litertlm` model file before it is atomically
/// renamed from its `.part` path into place (see
/// `doc/adr/0005-model-download-flow.md`).
///
/// Deliberately NOT a checksum/hash verification (that alternative was
/// considered and rejected in the ADR) — just a minimum-size check, cheap
/// enough to run synchronously on every completed download with no
/// pre-published checksum to maintain.
class ValidateDownloadedModelUseCase {
  const ValidateDownloadedModelUseCase();

  /// The smallest plausible size (in bytes) for a real `Gemma3-1B-IT`
  /// `dynamic_int4` `.litertlm` file. The real download is ~529 MB; this is
  /// set well below that (flutter-implementer: pick a concrete threshold,
  /// e.g. 100 MB) so a genuinely truncated/failed download (a `.part` file
  /// that stopped after a few KB/MB due to a dropped connection) is
  /// rejected, while leaving headroom for legitimate model-file size
  /// variance across future quantizations.
  static const int minValidSizeBytes = 100 * 1000 * 1000;

  /// Returns true if the file at [fileSizeBytes] passes the minimum-size
  /// sanity check. Pure function over a size, not a file path, so it needs
  /// no filesystem access to unit test.
  bool call({required int fileSizeBytes}) {
    return fileSizeBytes >= minValidSizeBytes;
  }
}

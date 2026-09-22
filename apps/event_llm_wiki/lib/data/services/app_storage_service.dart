import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Thin wrapper around `package:path_provider` that resolves the on-disk
/// paths this app writes the downloaded model to, and the small filesystem
/// operations `ModelDownloadRepositoryImpl` needs around them.
///
/// Abstracted so tests can substitute a `FakeAppStorageService` backed by a
/// temp directory or an in-memory map, with no real device storage
/// involved. Both [modelFilePath] and [modelPartFilePath] live under the
/// same app-storage directory (`getApplicationSupportDirectory()` is the
/// intended real backing — not `getTemporaryDirectory()`, since the OS may
/// reclaim temp storage and this ~529 MB download is expensive to redo).
abstract class AppStorageService {
  /// Final path of a validated, ready-to-use model file
  /// (`<app-storage>/model.litertlm`).
  Future<String> get modelFilePath;

  /// Path a download streams into before it is validated and atomically
  /// renamed to [modelFilePath] (`<app-storage>/model.litertlm.part`). See
  /// `doc/adr/0005-model-download-flow.md`.
  Future<String> get modelPartFilePath;

  /// True if a file exists at [modelFilePath]. Does NOT itself validate
  /// size/content — `ModelDownloadRepositoryImpl.checkLocalStatus()`
  /// combines this with a size check before reporting
  /// `ModelDownloadPhase.ready`.
  Future<bool> modelFileExists();

  /// Size in bytes of the file at [modelFilePath], or null if it does not
  /// exist.
  Future<int?> modelFileSizeBytes();

  /// Deletes [modelPartFilePath] if it exists. Used both to discard a stale
  /// `.part` file left over from a force-quit-mid-download on relaunch, and
  /// before starting a fresh download (this app's download is not
  /// resumable — see the ADR).
  Future<void> deletePartFileIfExists();

  /// Appends [bytes] to [modelPartFilePath], creating it if this is the
  /// first chunk of a fresh download.
  ///
  /// Gap-fill vs. the original architecture-phase stub: `ADR 0005`'s
  /// compliance rule requires "no `dart:io` `File`/`Directory` usage
  /// scattered outside `data/services/app_storage_service.dart`", but the
  /// original interface had no method for `ModelDownloadRepositoryImpl` to
  /// actually write the streamed bytes it receives from
  /// `ModelDownloadService` anywhere — this method (plus
  /// [closePartFileWriter]) closes that gap while keeping every `dart:io`
  /// file write confined to this one file, exactly as the ADR requires.
  Future<void> appendToPartFile(List<int> bytes);

  /// Flushes and closes whatever file handle [appendToPartFile] opened, if
  /// any. Safe to call even if [appendToPartFile] was never called (e.g. a
  /// download that failed before its first chunk). Must be called on every
  /// exit path of a download (success, validation failure, or stream
  /// error) so a partial file handle is never left open.
  Future<void> closePartFileWriter();

  /// Atomically renames [modelPartFilePath] to [modelFilePath] once
  /// `ValidateDownloadedModelUseCase` has accepted the completed download.
  Future<void> renamePartFileToModelFile();
}

/// Real implementation backed by `package:path_provider`.
class AppStorageServiceImpl implements AppStorageService {
  AppStorageServiceImpl({this.modelFileName = 'model.litertlm'});

  final String modelFileName;

  String? _cachedSupportDirPath;
  IOSink? _partFileWriter;

  Future<String> get _supportDirPath async {
    final cached = _cachedSupportDirPath;
    if (cached != null) return cached;
    final dir = await getApplicationSupportDirectory();
    _cachedSupportDirPath = dir.path;
    return dir.path;
  }

  @override
  Future<String> get modelFilePath async =>
      '${await _supportDirPath}/$modelFileName';

  @override
  Future<String> get modelPartFilePath async => '${await modelFilePath}.part';

  @override
  Future<bool> modelFileExists() async => File(await modelFilePath).exists();

  @override
  Future<int?> modelFileSizeBytes() async {
    final file = File(await modelFilePath);
    if (!await file.exists()) return null;
    return file.length();
  }

  @override
  Future<void> deletePartFileIfExists() async {
    final file = File(await modelPartFilePath);
    if (await file.exists()) {
      await file.delete();
    }
  }

  @override
  Future<void> appendToPartFile(List<int> bytes) async {
    var sink = _partFileWriter;
    if (sink == null) {
      sink = File(await modelPartFilePath).openWrite(mode: FileMode.append);
      _partFileWriter = sink;
    }
    sink.add(bytes);
    await sink.flush();
  }

  @override
  Future<void> closePartFileWriter() async {
    final sink = _partFileWriter;
    _partFileWriter = null;
    if (sink != null) {
      await sink.close();
    }
  }

  @override
  Future<void> renamePartFileToModelFile() async {
    final part = File(await modelPartFilePath);
    await part.rename(await modelFilePath);
  }
}

import 'package:file_picker/file_picker.dart';

/// Thin wrapper around `package:file_picker` restricted strictly to `.pdf` files.
///
/// **This is the ONLY file in StudyGemma allowed to import `package:file_picker`.**
abstract interface class PdfPickerService {
  /// Opens the native OS file picker filtered to `.pdf` files and returns the
  /// selected file path, or `null` if the user cancels.
  Future<String?> pickPdfPath();
}

/// Real implementation backed by [FilePicker.platform].
class PdfPickerServiceImpl implements PdfPickerService {
  const PdfPickerServiceImpl();

  @override
  Future<String?> pickPdfPath() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
    );
    if (result == null || result.files.isEmpty) {
      return null;
    }
    return result.files.first.path;
  }
}

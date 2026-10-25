# 0003. PDF-Only Ingestion Validation & Background `Isolate.run()` Text Extraction

- **Status**: accepted
- **Date**: 2026-10-24
- **Deciders**: flutter-architect

## Context

**StudyGemma** allows users to import study documents from local device storage. Two critical engineering constraints govern this flow:

1. **Strict PDF-Only Input Contract**: Users or external file providers might attempt to pass non-PDF files, renamed extensions, or corrupted/empty files. StudyGemma only supports PDF documents and must reject invalid files immediately with a clear, actionable domain error before starting the RAG pipeline.
2. **60fps / 120fps Frame Budget Preservation**: Parsing a 50–300 page PDF dictionary structure, decompressing Flate streams, and extracting page-by-page text is CPU-intensive synchronous work. Running PDF parsing on the main Flutter UI isolate would block frame rendering (causing severe jank and frozen progress animations during ingestion). Furthermore, the PDF extractor must run in `flutter test` without requiring platform channels or a running Android/iOS host.

## Decision

### 1. Defense-in-Depth PDF-Only Validation
Enforce PDF-only ingestion at two consecutive layers:
1. **OS Picker Filter (`PdfPickerService`)**: Wraps `package:file_picker` (`^10.3.3`) configured strictly with `type: FileType.custom` and `allowedExtensions: const ['pdf']`.
2. **Extension & `%PDF-` Magic Header Verification (`PdfExtractorService` / `DocumentIngestionRepositoryImpl`)**:
   - Verify the selected file path ends with `.pdf` (case-insensitive).
   - Verify the file exists, is non-empty (`length >= 5`), and starts with the 5-byte ASCII PDF magic header `[0x25, 0x50, 0x44, 0x46, 0x2D]` (`%PDF-`).
   - If validation fails, throw a typed `InvalidPdfException` (subclass of `AppException`) before invoking the PDF parser or touching `RagIndex`.

### 2. Pure-Dart PDF Extraction Inside `Isolate.run()` (`PdfExtractorService`)
Adopt **`syncfusion_flutter_pdf: ^31.1.19`** (100% pure-Dart PDF parser) executed inside **`Isolate.run()`** in `PdfExtractorService` (`lib/data/services/pdf_extractor_service.dart`):

```dart
Future<List<ExtractedPdfPage>> extractPages(String filePath) async {
  return Isolate.run(() => _extractPagesSync(filePath));
}
```

Inside the background isolate worker (`_extractPagesSync`):
1. Read the file bytes and verify the `%PDF-` magic header.
2. Instantiate `final document = PdfDocument(inputBytes: bytes);` inside a `try / finally` block that always calls `document.dispose()`.
3. Extract text page-by-page using `PdfTextExtractor(document).extractText(startPageIndex: i, endPageIndex: i)` and construct 1-based `ExtractedPdfPage(pageNumber: i + 1, text: pageText)` objects.
4. If the PDF contains zero extractable text across all pages (e.g., a scanned image-only PDF without an OCR text layer), throw `EmptyPdfTextException` so the UI informs the student that the PDF has no selectable text layer.

### 3. Real-Time Stage Progress Streaming (`Stream<IngestionProgress>`)
`DocumentIngestionRepository.ingestPdfStream(PickedPdfFile file)` yields granular `IngestionProgress` snapshots across four sequential stages:
- `IngestionStage.validating`: Verifying `.pdf` extension and `%PDF-` header.
- `IngestionStage.extracting`: Running background isolate page extraction.
- `IngestionStage.chunking`: Executing `ChunkDocumentUseCase` to produce `List<DocumentChunk>` with page metadata.
- `IngestionStage.embedding`: Indexing chunks sequentially through `RagIndexRepository.indexChunks(...)` with live `(currentChunk / totalChunks)` progress updates, then persisting the `StudyDocument` summary to Hive (`IngestionStage.completed`).

## Alternatives Considered

- **Platform-Channel PDF Renderers (`pdfx`, `printing`, Android `PdfRenderer`)**:
  - *Rejected*: Android's native `PdfRenderer` only rasterizes pages to bitmaps and provides no text extraction API. Native PDF plugins also require platform channels that cannot execute inside pure-Dart `flutter test` suites.
- **Parsing PDFs on the Main Isolate**:
  - *Rejected*: Violates the 16ms (60fps) / 8ms (120fps) Flutter frame budget rule. Extracting text from a multi-page PDF blocks the event loop for hundreds of milliseconds, freezing the `IngestionProgressCard` animation.

## Consequences

- **Zero UI Jank During Ingestion**: All byte reading, PDF decompression, and CMap glyph-to-Unicode extraction happen on a short-lived worker isolate via `Isolate.run()`, leaving the main UI isolate free to render smooth 60/120fps progress transitions.
- **Deterministic Pure-Dart Unit Testing**: Because `syncfusion_flutter_pdf` is pure Dart, unit tests can generate real in-memory PDFs using `PdfDocument()` + `page.graphics.drawString(...)` and test `PdfExtractorService` directly in `flutter test` without mocks or device emulators, while repository/view-model tests can inject `FakePdfExtractorService`.
- **Explicit Scanned-PDF Handling**: Image-only PDFs are caught cleanly via `EmptyPdfTextException` before any empty chunks are sent to `EmbeddingGemma 2`.

## Compliance

`flutter-reviewer` checks:
- [ ] `package:file_picker` is imported **ONLY** in `lib/data/services/pdf_picker_service.dart` and enforces `FileType.custom` with `allowedExtensions: ['pdf']`.
- [ ] `package:syncfusion_flutter_pdf` is imported **ONLY** in `lib/data/services/pdf_extractor_service.dart` (and its dedicated unit test).
- [ ] `PdfExtractorService` validates the `%PDF-` magic header (`[0x25, 0x50, 0x44, 0x46, 0x2D]`), executes `PdfDocument` parsing inside `Isolate.run()`, and always calls `document.dispose()` in a `finally` block.
- [ ] Scanned or blank PDFs with zero extractable text fail gracefully with a typed `AppException` (`EmptyPdfTextException`) rather than indexing empty chunks.

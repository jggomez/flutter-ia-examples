import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../domain/models/ingestion_progress.dart';
import '../../../../domain/models/study_document.dart';
import '../../../providers/repository_providers.dart';
import '../../chat/view_models/study_chat_view_model.dart';

/// Immutable UI state for the PDF Study Library & RAG Ingestion screen.
class DocumentLibraryState {
  const DocumentLibraryState({
    required this.documents,
    this.activeIngestion,
    this.errorMessage,
  });

  final List<StudyDocument> documents;
  final IngestionProgress? activeIngestion;
  final String? errorMessage;

  DocumentLibraryState copyWith({
    List<StudyDocument>? documents,
    IngestionProgress? activeIngestion,
    bool clearActiveIngestion = false,
    String? errorMessage,
    bool clearErrorMessage = false,
  }) {
    return DocumentLibraryState(
      documents: documents ?? this.documents,
      activeIngestion: clearActiveIngestion
          ? null
          : (activeIngestion ?? this.activeIngestion),
      errorMessage: clearErrorMessage
          ? null
          : (errorMessage ?? this.errorMessage),
    );
  }
}

/// Manages the indexed PDF catalog, 4-stage RAG ingestion progress streaming,
/// and document deletion (see ADR 0004).
class DocumentLibraryViewModel extends AsyncNotifier<DocumentLibraryState> {
  @override
  Future<DocumentLibraryState> build() async {
    final documents = await ref
        .watch(documentIngestionRepositoryProvider)
        .getAllDocuments();
    return DocumentLibraryState(documents: documents);
  }

  /// Opens the native PDF picker and streams the 4-stage ingestion pipeline
  /// (`validating` → `extracting` → `chunking` → `embedding` → `completed`).
  Future<void> pickAndIngestPdf() async {
    final repository = ref.read(documentIngestionRepositoryProvider);
    final current =
        state.value ?? const DocumentLibraryState(documents: <StudyDocument>[]);

    String? pickedPath;
    try {
      pickedPath = await repository.pickPdfPath();
    } catch (error) {
      state = AsyncData(
        current.copyWith(clearActiveIngestion: true, errorMessage: '$error'),
      );
      return;
    }

    if (pickedPath == null) return;

    try {
      await for (final progress in repository.ingestPdf(filePath: pickedPath)) {
        final latestDocs = state.value?.documents ?? current.documents;
        if (progress.stage == IngestionStage.completed) {
          final updatedDocs = await repository.getAllDocuments();
          state = AsyncData(
            DocumentLibraryState(
              documents: updatedDocs,
              activeIngestion: null,
              errorMessage: null,
            ),
          );
        } else if (progress.stage == IngestionStage.failed) {
          state = AsyncData(
            DocumentLibraryState(
              documents: latestDocs,
              activeIngestion: null,
              errorMessage:
                  progress.errorMessage ??
                  (progress.message.isNotEmpty
                      ? progress.message
                      : 'PDF ingestion failed.'),
            ),
          );
        } else {
          state = AsyncData(
            DocumentLibraryState(
              documents: latestDocs,
              activeIngestion: progress,
              errorMessage: null,
            ),
          );
        }
      }
    } catch (error) {
      final latestDocs = state.value?.documents ?? current.documents;
      state = AsyncData(
        DocumentLibraryState(
          documents: latestDocs,
          activeIngestion: null,
          errorMessage: '$error',
        ),
      );
    }
  }

  /// Deletes [docId] from the catalog and vector index, clears any stale
  /// document filter in Study Chat, and refreshes the document list.
  Future<void> deleteDocument(String docId) async {
    final repository = ref.read(documentIngestionRepositoryProvider);
    final current =
        state.value ?? const DocumentLibraryState(documents: <StudyDocument>[]);

    try {
      await repository.deleteDocument(docId);
      if (ref.read(selectedDocumentFilterProvider) == docId) {
        ref.read(selectedDocumentFilterProvider.notifier).selectDocument(null);
      }
      final updatedDocs = await repository.getAllDocuments();
      state = AsyncData(
        current.copyWith(documents: updatedDocs, clearErrorMessage: true),
      );
    } catch (error) {
      state = AsyncData(current.copyWith(errorMessage: '$error'));
    }
  }
}

final documentLibraryViewModelProvider =
    AsyncNotifierProvider.autoDispose<
      DocumentLibraryViewModel,
      DocumentLibraryState
    >(DocumentLibraryViewModel.new, retry: (retryCount, error) => null);

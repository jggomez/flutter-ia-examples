import 'study_document.dart';

/// Sequential stages of the on-device PDF RAG ingestion pipeline.
enum IngestionStage {
  idle,
  validating,
  extracting,
  chunking,
  embedding,
  completed,
  failed,
}

/// Real-time progress snapshot emitted during PDF ingestion.
class IngestionProgress {
  const IngestionProgress({
    required this.stage,
    this.current = 0,
    this.total = 0,
    this.message = '',
    this.document,
    this.errorMessage,
  });

  final IngestionStage stage;
  final int current;
  final int total;
  final String message;
  final StudyDocument? document;
  final String? errorMessage;

  double get progress {
    if (stage == IngestionStage.completed) return 1.0;
    if (total <= 0) return 0.0;
    return (current / total).clamp(0.0, 1.0);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is IngestionProgress &&
        other.stage == stage &&
        other.current == current &&
        other.total == total &&
        other.message == message &&
        other.document == document &&
        other.errorMessage == errorMessage;
  }

  @override
  int get hashCode =>
      Object.hash(stage, current, total, message, document, errorMessage);
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../domain/models/study_document.dart';
import '../../../core/widgets/ingestion_progress_card.dart';
import '../../chat/view_models/study_chat_view_model.dart';
import '../view_models/document_library_view_model.dart';

/// Displays the user's indexed PDF study library, a prominent
/// `"Import Study PDF (.pdf only)"` action card, live 4-stage RAG ingestion
/// progress, and per-document `"Ask AI about this PDF"` / delete actions.
class DocumentLibraryScreen extends ConsumerWidget {
  const DocumentLibraryScreen({super.key, this.onNavigateToChat});

  final VoidCallback? onNavigateToChat;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final libraryState = ref.watch(documentLibraryViewModelProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.library_books_rounded, size: 22),
            SizedBox(width: 10),
            Text('PDF Study Library'),
          ],
        ),
      ),
      body: SafeArea(
        child: libraryState.when(
          data: (state) =>
              _LibraryBody(state: state, onNavigateToChat: onNavigateToChat),
          loading: () => const Center(
            child: CircularProgressIndicator(key: ValueKey('libraryLoading')),
          ),
          error: (error, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Error loading library: $error',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LibraryBody extends ConsumerWidget {
  const _LibraryBody({required this.state, this.onNavigateToChat});

  final DocumentLibraryState state;
  final VoidCallback? onNavigateToChat;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(documentLibraryViewModelProvider.notifier);
    final isIngesting = state.activeIngestion != null;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: [
        _ImportPdfActionCard(
          isBusy: isIngesting,
          onImportPressed: () => notifier.pickAndIngestPdf(),
        ),
        if (state.activeIngestion != null) ...[
          const SizedBox(height: 14),
          IngestionProgressCard(progress: state.activeIngestion!),
        ],
        if (state.errorMessage != null) ...[
          const SizedBox(height: 14),
          _IngestionErrorBanner(message: state.errorMessage!),
        ],
        const SizedBox(height: 18),
        if (state.documents.isEmpty)
          const _EmptyLibraryWorkflowCard()
        else ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              'Indexed Study Documents (${state.documents.length})',
              style: Theme.of(context).textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
          for (final doc in state.documents) ...[
            _StudyDocumentCard(
              document: doc,
              onAskAi: () {
                ref
                    .read(selectedDocumentFilterProvider.notifier)
                    .selectDocument(doc.id);
                onNavigateToChat?.call();
              },
              onDelete: () => notifier.deleteDocument(doc.id),
            ),
            const SizedBox(height: 12),
          ],
        ],
      ],
    );
  }
}

class _ImportPdfActionCard extends StatelessWidget {
  const _ImportPdfActionCard({
    required this.isBusy,
    required this.onImportPressed,
  });

  final bool isBusy;
  final VoidCallback onImportPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      color: colorScheme.primaryContainer.withAlpha(110),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: colorScheme.primary.withAlpha(90)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                Icons.upload_file_rounded,
                size: 26,
                color: colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Add Textbook or Lecture Notes',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Extracts pages in a background isolate, chunks with 40-word overlap, and indexes 768-dim vectors into SQLite vec0.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    key: const ValueKey('importPdfButton'),
                    onPressed: isBusy ? null : onImportPressed,
                    icon: const Icon(Icons.picture_as_pdf_rounded, size: 18),
                    label: const Text('Import Study PDF (.pdf only)'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StudyDocumentCard extends StatelessWidget {
  const _StudyDocumentCard({
    required this.document,
    required this.onAskAi,
    required this.onDelete,
  });

  final StudyDocument document;
  final VoidCallback onAskAi;
  final VoidCallback onDelete;

  String _formatDate(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      key: ValueKey('documentCard_${document.id}'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.description_rounded,
                    color: colorScheme.onSecondaryContainer,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        document.title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${document.fileName} · Indexed ${_formatDate(document.indexedAt)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  key: ValueKey('deleteDocButton_${document.id}'),
                  tooltip: 'Delete PDF from RAG index',
                  icon: Icon(
                    Icons.delete_outline_rounded,
                    color: colorScheme.error,
                  ),
                  onPressed: onDelete,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _MetadataBadge(
                  icon: Icons.auto_stories_outlined,
                  label: '${document.pageCount} pages',
                  backgroundColor: colorScheme.primaryContainer,
                  foregroundColor: colorScheme.onPrimaryContainer,
                ),
                _MetadataBadge(
                  icon: Icons.hub_outlined,
                  label: '${document.chunkCount} chunks in SQLite vec0',
                  backgroundColor: colorScheme.tertiaryContainer,
                  foregroundColor: colorScheme.onTertiaryContainer,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonalIcon(
                key: ValueKey('askAiButton_${document.id}'),
                onPressed: onAskAi,
                icon: const Icon(Icons.chat_bubble_outline_rounded, size: 17),
                label: const Text('Ask AI about this PDF'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetadataBadge extends StatelessWidget {
  const _MetadataBadge({
    required this.icon,
    required this.label,
    required this.backgroundColor,
    required this.foregroundColor,
  });

  final IconData icon;
  final String label;
  final Color backgroundColor;
  final Color foregroundColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: foregroundColor),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: foregroundColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyLibraryWorkflowCard extends StatelessWidget {
  const _EmptyLibraryWorkflowCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      key: const ValueKey('emptyLibraryState'),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.bolt_rounded, color: colorScheme.primary, size: 22),
                const SizedBox(width: 8),
                Text(
                  '4-Step On-Device PDF RAG Workflow',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'No study PDFs are indexed yet. Import a textbook chapter, paper, or lecture handout above:',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 14),
            const _WorkflowStepItem(
              number: '1',
              title: 'Validate PDF',
              description:
                  'Verifies .pdf extension and %PDF- magic header locally.',
            ),
            const SizedBox(height: 8),
            const _WorkflowStepItem(
              number: '2',
              title: 'Extract Pages in Background Isolate',
              description:
                  'Extracts selectable page text without dropping UI frames.',
            ),
            const SizedBox(height: 8),
            const _WorkflowStepItem(
              number: '3',
              title: 'Sliding-Window Chunking',
              description:
                  'Splits pages into ~220-word windows with 40-word overlap.',
            ),
            const SizedBox(height: 8),
            const _WorkflowStepItem(
              number: '4',
              title: 'EmbeddingGemma 2 + SQLite vec0',
              description: 'Embeds 768-dim vectors and stores them in study_gemma_rag.sqlite.',
            ),
          ],
        ),
      ),
    );
  }
}

class _WorkflowStepItem extends StatelessWidget {
  const _WorkflowStepItem({
    required this.number,
    required this.title,
    required this.description,
  });

  final String number;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer,
            shape: BoxShape.circle,
          ),
          child: Text(
            number,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: colorScheme.onPrimaryContainer,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                description,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _IngestionErrorBanner extends StatelessWidget {
  const _IngestionErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(
            Icons.warning_amber_rounded,
            color: colorScheme.onErrorContainer,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: colorScheme.onErrorContainer,
                fontWeight: FontWeight.w600,
                fontSize: 12.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

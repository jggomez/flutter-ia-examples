import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:genui/genui.dart';

import '../../../../domain/repositories/selling_agent_repository.dart';
import '../../../providers/repository_providers.dart';
import '../view_models/selling_session_state.dart';
import '../view_models/selling_session_view_model.dart';
import 'widgets/processing_banner.dart';

/// Host screen rendering the active A2UI v0.9 [Surface] for the selling flow.
class DynamicSurfaceHostScreen extends ConsumerWidget {
  /// Creates a [DynamicSurfaceHostScreen].
  const DynamicSurfaceHostScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final SellingSessionState sessionState = ref.watch(
      sellingSessionViewModelProvider,
    );
    final SellingAgentRepository agentRepository = ref.watch(
      sellingAgentRepositoryProvider,
    );
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    final String? activeSurfaceId = sessionState.activeSurfaceId;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Snap & Sell'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Start Over',
            onPressed: () {
              ref.read(sellingSessionViewModelProvider.notifier).resetSession();
            },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: Stack(
          children: <Widget>[
            IgnorePointer(
              key: const Key('surface_host_ignore_pointer'),
              ignoring: sessionState.isProcessing,
              child: Column(
                children: <Widget>[
                  if (sessionState.errorMessage != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: colorScheme.errorContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: <Widget>[
                            Icon(
                              Icons.error_outline,
                              color: colorScheme.onErrorContainer,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                sessionState.errorMessage!,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onErrorContainer,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: () {
                                ref
                                    .read(
                                      sellingSessionViewModelProvider.notifier,
                                    )
                                    .clearError();
                              },
                              child: const Text('Dismiss'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (sessionState.isProcessing)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: ProcessingBanner(
                        message:
                            sessionState.lastAgentText ??
                            (sessionState.status ==
                                    SellingFlowStatus.submittingAction
                                ? 'Updating listing with Gemini...'
                                : 'Analyzing item with Gemini...'),
                      ),
                    ),
                  Expanded(
                    child: activeSurfaceId == null
                        ? _EmptySurfacePlaceholder(
                            isProcessing: sessionState.isProcessing,
                          )
                        : SingleChildScrollView(
                            padding: const EdgeInsets.all(16),
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 220),
                              child: KeyedSubtree(
                                key: ValueKey<String>(activeSurfaceId),
                                child: Surface(
                                  surfaceContext: agentRepository
                                      .surfaceController
                                      .contextFor(activeSurfaceId),
                                  defaultBuilder: (BuildContext context) {
                                    return const Padding(
                                      padding: EdgeInsets.all(24),
                                      child: Center(
                                        child: Text('Preparing surface...'),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                          ),
                  ),
                ],
              ),
            ),
            if (sessionState.isProcessing)
              Positioned.fill(
                child: ColoredBox(
                  color: Colors.black.withValues(alpha: 0.35),
                  child: Center(
                    child: Card(
                      elevation: 8,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 20,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            const SizedBox(
                              width: 36,
                              height: 36,
                              child: CircularProgressIndicator(strokeWidth: 3),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Procesando...',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 240),
                              child: Text(
                                sessionState.lastAgentText ??
                                    (sessionState.status ==
                                            SellingFlowStatus.submittingAction
                                        ? 'Actualizando publicación con Gemini...'
                                        : 'Analizando con Gemini...'),
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _EmptySurfacePlaceholder extends StatelessWidget {
  const _EmptySurfacePlaceholder({required this.isProcessing});

  final bool isProcessing;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              isProcessing
                  ? Icons.auto_awesome_motion
                  : Icons.burst_mode_outlined,
              size: 48,
              color: colorScheme.primary,
            ),
            const SizedBox(height: 12),
            Text(
              isProcessing
                  ? 'Inspecting your photo and building a tailored form...'
                  : 'Waiting for selling surface...',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Alias matching prompt naming (`SellingFlowScreen`).
typedef SellingFlowScreen = DynamicSurfaceHostScreen;

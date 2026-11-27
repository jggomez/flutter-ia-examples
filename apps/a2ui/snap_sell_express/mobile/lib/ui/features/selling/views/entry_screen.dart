import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../domain/models/captured_photo.dart';
import '../view_models/selling_session_state.dart';
import '../view_models/selling_session_view_model.dart';

/// Native entry screen where the seller initiates the Snap & Sell flow.
class EntryScreen extends ConsumerWidget {
  /// Creates an [EntryScreen].
  const EntryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final SellingSessionState sessionState = ref.watch(
      sellingSessionViewModelProvider,
    );
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    final bool isBusy = sessionState.isProcessing;

    return Scaffold(
      appBar: AppBar(title: const Text('Snap & Sell')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Column(
                  children: <Widget>[
                    Icon(
                      Icons.auto_awesome,
                      size: 56,
                      color: colorScheme.primary,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '¿Qué quieres vender?',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Take one photo and let Gemini build your complete marketplace listing.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.center,
                      children: const <Widget>[
                        Chip(
                          avatar: Icon(Icons.directions_car_filled, size: 18),
                          label: Text('Cars'),
                        ),
                        Chip(
                          avatar: Icon(Icons.two_wheeler, size: 18),
                          label: Text('Motorcycles'),
                        ),
                        Chip(
                          avatar: Icon(Icons.smartphone, size: 18),
                          label: Text('Phones'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              FilledButton.icon(
                onPressed: isBusy
                    ? null
                    : () => ref
                          .read(sellingSessionViewModelProvider.notifier)
                          .startSessionWithPhoto(PhotoCaptureSource.camera),
                icon: isBusy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.camera_alt_outlined),
                label: const Text('Take Photo'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: isBusy
                    ? null
                    : () => ref
                          .read(sellingSessionViewModelProvider.notifier)
                          .startSessionWithPhoto(PhotoCaptureSource.gallery),
                icon: isBusy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.photo_library_outlined),
                label: const Text('Choose from Gallery'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

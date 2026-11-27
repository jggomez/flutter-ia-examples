import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/app_theme.dart';
import 'ui/features/selling/view_models/selling_session_state.dart';
import 'ui/features/selling/view_models/selling_session_view_model.dart';
import 'ui/features/selling/views/dynamic_surface_host_screen.dart';
import 'ui/features/selling/views/entry_screen.dart';

/// Root Material 3 application widget for Snap & Sell.
class SnapSellApp extends ConsumerWidget {
  /// Creates a [SnapSellApp].
  const SnapSellApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final SellingSessionState sessionState = ref.watch(
      sellingSessionViewModelProvider,
    );
    final bool showEntry =
        sessionState.status == SellingFlowStatus.idle &&
        sessionState.activeSurfaceId == null &&
        sessionState.errorMessage == null;

    return MaterialApp(
      title: 'Snap & Sell',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      home: showEntry ? const EntryScreen() : const DynamicSurfaceHostScreen(),
    );
  }
}

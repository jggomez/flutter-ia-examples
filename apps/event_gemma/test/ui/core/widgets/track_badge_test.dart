import 'package:event_gemma/domain/models/conference_track.dart';
import 'package:event_gemma/ui/core/widgets/track_badge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders Engineering track badge with correct label', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: TrackBadge(track: ConferenceTrack.engineering)),
      ),
    );

    expect(find.text('Engineering'), findsOneWidget);
  });

  testWidgets('renders Product & Design track badge with correct label', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: TrackBadge(track: ConferenceTrack.productAndDesign),
        ),
      ),
    );

    expect(find.text('Product & Design'), findsOneWidget);
  });
}

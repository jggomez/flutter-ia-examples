import 'package:event_llm_wiki/domain/models/citation.dart';
import 'package:event_llm_wiki/ui/core/widgets/citation_chip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders the citation talk title', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CitationChip(
            citation: const Citation(
              talkId: 'talk-001',
              talkTitle: 'On-Device LLMs',
            ),
            onTap: () {},
          ),
        ),
      ),
    );

    expect(find.text('On-Device LLMs'), findsOneWidget);
  });

  testWidgets('calls onTap when tapped', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CitationChip(
            citation: const Citation(
              talkId: 'talk-001',
              talkTitle: 'On-Device LLMs',
            ),
            onTap: () => tapped = true,
          ),
        ),
      ),
    );

    await tester.tap(find.byType(CitationChip));
    await tester.pump();

    expect(tapped, isTrue);
  });
}

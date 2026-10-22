import '../models/conference_day.dart';
import '../models/conference_track.dart';
import '../models/retrieved_talk.dart';

/// Composes the final prompt text sent to `ChatEngineRepository.sendMessage`
/// from the user's raw question plus the talks
/// `RetrieveRelevantTalksUseCase` retrieved for it.
///
/// This is the "G" (generation grounding) half of this app's RAG pipeline —
/// it is a pure string-composition use case, not an inference call. Its
/// output is plain text; the model has no structured/function-calling
/// awareness of "talks" as a type.
///
/// The composed prompt MUST, when [retrievedTalks] is empty, explicitly
/// instruct the model that no matching talk was found in the agenda and it
/// should say so honestly rather than invent an answer (this is the
/// concrete mechanism behind the "honest 'not in this agenda' answer, no
/// citation chips" acceptance check in PLAN.md's phase 12). When
/// [retrievedTalks] is non-empty, the prompt should ground the answer in
/// those talks' title/speakers/abstract/time content and instruct the model
/// not to answer beyond what they contain.
///
/// Citations shown to the user are always [retrievedTalks] itself (computed
/// before generation), never parsed back out of the model's free-text
/// response — this use case's output text has no special citation syntax
/// for `ChatViewModel` to parse.
class BuildChatPromptUseCase {
  const BuildChatPromptUseCase();

  /// Builds the full prompt to send to the engine for [userQuestion], given
  /// the (possibly empty) [retrievedTalks] context.
  String call({
    required String userQuestion,
    required List<RetrievedTalk> retrievedTalks,
  }) {
    final buffer = StringBuffer()
      ..writeln(
        'You are Event Gemma, the official on-device AI assistant for the On-Device AI Conference 2026.',
      )
      ..writeln()
      ..writeln(
        'RULES:\n'
        '1. LANGUAGE: Detect the language of the user\'s question and respond in that EXACT same language (e.g., if the user asks in Spanish, reply in Spanish; if in English, reply in English).\n'
        '2. GROUNDING: Answer ONLY using the information in the context below — do not answer beyond what it contains, and do not invent details.\n'
        '3. CITATIONS: When mentioning or recommending talks, explicitly mention the talk Title and Speaker name so attendees know where to go.',
      )
      ..writeln();

    if (retrievedTalks.isEmpty) {
      buffer
        ..writeln(
          'Context: no matching talk was found in this agenda for the '
          "question below. Honestly tell the user you couldn't find a "
          'relevant talk in the agenda — do not guess or make up an '
          'answer.',
        )
        ..writeln();
    } else {
      buffer
        ..writeln(
          'CONFERENCE OVERVIEW:\n'
          'The conference spans 2 days (Day 1 & Day 2) with 2 simultaneous tracks: "Engineering" and "Product & Design", featuring 20 talks in total.\n',
        )
        ..writeln('Context (talks from the agenda):');
      for (var i = 0; i < retrievedTalks.length; i++) {
        final talk = retrievedTalks[i].talk;
        final speakerNames = talk.speakers.map((s) => s.name).join(', ');
        buffer
          ..writeln('${i + 1}. Title: ${talk.title}')
          ..writeln('   Speakers: $speakerNames')
          ..writeln('   Day: ${talk.day.label}')
          ..writeln('   Track: ${talk.track.label}')
          ..writeln('   Abstract: ${talk.abstract}');
      }
      buffer.writeln();
    }

    buffer
      ..writeln('Question: $userQuestion')
      ..write('Answer:');

    return buffer.toString();
  }
}

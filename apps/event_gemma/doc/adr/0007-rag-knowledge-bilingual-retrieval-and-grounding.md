# 0007. Bilingual Lexical RAG, Hybrid System Instruction Grounding, and Knowledge Retrieval

- **Status**: accepted
- **Date**: 2026-10-22
- **Deciders**: flutter-architect

## Context

`event_llm_wiki` operates as a 100% offline, on-device AI conference companion. It bundles an agenda of 20 talks across 2 days and 2 tracks (`assets/agenda.json`) and runs a local Gemma 3 1B-IT model (`.litertlm`, ~529 MB, 4096 context window) via `flutter_edge_ai_litertlm` (ADR 0006).

### Problem Statement

During real-world on-device testing, user queries about talks in Spanish (e.g., *"¿De qué tratan las charlas?"*, *"¿Qué charlas hay?"*, *"charlas de flutter"*, *"quién habla de cuantización"*) or general exploratory questions in English (*"What talks are there?"*, *"Give me an overview of the conference"*) resulted in complete grounding failures:
1. The assistant answered off-topic or hallucinated wildly (*"responde otra cosa"*).
2. The assistant refused to answer, stating that no relevant talk could be found in the agenda.
3. The UI rendered 0 citation chips, leaving the user with an empty, unhelpful experience.

### Root Cause Analysis

Investigation identified five compounding architectural defects across retrieval, prompt composition, and native runtime session management:

1. **Diacritic Stripping in Token Normalization**:
   In `RetrieveRelevantTalksUseCase`, `_normalize()` applied `text.toLowerCase().replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')`.
   In Spanish, diacritics and letters outside ASCII `a-z` are stripped or broken:
   - `qué` → `qu`
   - `cuáles` → `cu les`
   - `cuantización` → `cuantizaci n`
   - `diseño` → `dise o`
   This corrupted keyword tokens before scoring could even begin.

2. **Cross-Lingual Vocabulary Disconnect**:
   `assets/agenda.json` is authored in English. Common Spanish domain vocabulary has zero literal string overlap with the English corpus:
   - `charlas` / `sesiones` / `platicas` vs. `talk` / `session`
   - `ponentes` / `expositores` vs. `speaker`
   - `horario` / `cronograma` / `evento` vs. `schedule` / `agenda` / `conference`
   - `ia` / `inteligencia artificial` vs. `ai` / `llm` / `on-device`
   Consequently, queries in Spanish scored zero across all fields.

3. **Broad / Exploratory Query Blindspot**:
   Even in English, questions such as *"What talks are in this conference?"* scored zero. Individual talk abstracts contain domain specifics (*quantization*, *NPU*, *Riverpod*, *battery*), but do not contain the literal meta-word *"talk"* or *"agenda"*.

4. **The Negative Prompting Trap (ADR 0002 Fallback)**:
   Per ADR 0002, when zero talks scored above zero, `RetrieveRelevantTalksUseCase` returned `[]`. In turn, `BuildChatPromptUseCase` emitted:
   ```text
   Context: no matching talk was found in this agenda for the question below.
   Honestly tell the user you couldn't find a relevant talk in the agenda —
   do not guess or make up an answer.
   ```
   For broad overview inquiries, this forced an unnatural rejection. Furthermore, Gemma 3 1B frequently ignored the negative instruction and hallucinated general pretraining associations.

5. **Lack of Language Matching & Persona Grounding**:
   `BuildChatPromptUseCase` contained no directive instructing the model to reply in the user's input language. When a Spanish query was passed, the model either defaulted to English or mixed languages inconsistently.

6. **Native Session Prompt Compounding in `LitertLmServiceImpl`**:
   `LitertLmServiceImpl` initialized `InferenceChat` without `systemInstruction`. On each user turn, the entire multi-line system prompt, contextual talk dump, and user query was fed into `_chat.addQueryChunk(Message.text(text: prompt, isUser: true))`.
   Because `InferenceChat` retains history turn-after-turn, system instructions and previous RAG contexts accumulated in the conversation history, rapidly polluting Gemma 3 1B's 4,096-token context window with duplicate instructions.

---

## Architectural Analysis: Function Calling vs. Hybrid System Grounding

The user posed the following architectural question:
> *"¿El modelo no soporta un cache en system prompt y pasarle eso, o cómo crees que se pueda hacer? ¿O una función calling que vaya y consulte esto?"*

We evaluated two fundamental design paths:

### Alternative A: Function Calling (Tool Calling)
- **Mechanism**: Register a Dart callback `searchTalks(query)` as a `Tool` via `flutter_edge_ai`. The model parses the user request, outputs a tool call JSON object, Dart executes lexical search and returns talk objects, and a second inference pass generates the natural language reply.
- **Evaluation & Drawbacks on 1B Edge Models**:
  1. **Latency Multiplication**: Running two complete inference passes on mobile hardware (CPU/NPU) doubles turn latency from ~3s to 6–10s, degrading interactive mobile chat.
  2. **JSON Schema Fragility**: Gemma 3 1B-IT is a lightweight 1-billion parameter model. While Gemma 4 E2B/E4B or larger cloud models handle tool calling reliably, 1B models exhibit frequent schema syntax failures, hallucinated parameter names, and tool-invocation omissions when prompted in non-English languages.
  3. **Architectural Mismatch**: Function calling is justified when querying unbounded, dynamic, or remote databases. The conference agenda is a fixed, small corpus of only 20 records. Adding tool-calling machinery introduces substantial complexity for zero scale advantage.

### Alternative B: Hybrid Grounding (Full Agenda in System Instruction + Dart Citation Scorer) [SELECTED]
- **Mechanism**:
  1. **Context Window Feasibility**: The full `assets/agenda.json` comprises exactly 20 talks. Formatted concisely (title, speakers, day, track, abstract), the entire corpus is ~1,500 tokens. Gemma 3 1B-IT provides a 4,096-token context window. The entire conference directory comfortably fits in the initial prompt or session context, leaving >2,500 tokens for multi-turn dialogue and output generation.
  2. **KV-Cache Prefill**: `flutter_edge_ai_litertlm` supports `model.createChat(systemInstruction: ...)` (or initializing a static system context). LiteRT-LM compiles and caches the system instructions once, so the model has permanent, global knowledge of the conference without tool calling.
  3. **Dual Role Division**:
     - **Generation Grounding (Model Knowledge)**: Handled by the comprehensive agenda knowledge base provided to the model. The model understands all 20 talks and can answer cross-cutting, general, and thematic questions in both Spanish and English.
     - **UI Citation Grounding (Dart Scorer)**: Handled deterministically by `RetrieveRelevantTalksUseCase`. It identifies the most relevant 1–3 talks (or top keynote overviews for general queries) solely to render clickable `CitationChip`s in Flutter, allowing users to navigate directly to `TalkDetailScreen`.

---

## Decision

### 1. Bilingual Normalization & Synonym Expansion (`RetrieveRelevantTalksUseCase`)

Refactor `RetrieveRelevantTalksUseCase` in `lib/domain/use_cases/retrieve_relevant_talks_use_case.dart` to support bilingual tokenization and semantic synonym expansion:

#### A. Diacritic Stripping & Character Normalization
Replace the ASCII regex with diacritic normalization before tokenization:
```dart
String _stripDiacritics(String text) {
  return text
      .replaceAll(RegExp(r'[áàäâ]', caseSensitive: false), 'a')
      .replaceAll(RegExp(r'[éèëê]', caseSensitive: false), 'e')
      .replaceAll(RegExp(r'[íìïî]', caseSensitive: false), 'i')
      .replaceAll(RegExp(r'[óòöô]', caseSensitive: false), 'o')
      .replaceAll(RegExp(r'[úùüû]', caseSensitive: false), 'u')
      .replaceAll(RegExp(r'[ñ]', caseSensitive: false), 'n')
      .replaceAll(RegExp(r'[ç]', caseSensitive: false), 'c');
}
```
After diacritic stripping, lowercase the text and remove all remaining non-alphanumeric characters: `replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')`.

#### B. Comprehensive Bilingual Stopwords
Filter both English and Spanish conversational stopwords:
```dart
static const Set<String> _stopwords = {
  // English
  'a', 'an', 'the', 'is', 'are', 'was', 'were', 'be', 'been', 'being',
  'in', 'on', 'at', 'to', 'of', 'for', 'and', 'or', 'but', 'with',
  'about', 'what', 'which', 'who', 'whom', 'whose', 'when', 'where',
  'why', 'how', 'this', 'that', 'these', 'those', 'do', 'does', 'did',
  'tell', 'me', 'can', 'could', 'would', 'should', 'will', 'shall',
  'i', 'you', 'it', 'there', 'any', 'some', 'please', 'give', 'show',
  'us', 'my', 'your',

  // Spanish
  'de', 'la', 'el', 'los', 'las', 'un', 'una', 'unos', 'unas', 'y',
  'e', 'o', 'u', 'en', 'a', 'para', 'por', 'con', 'sin', 'sobre',
  'entre', 'del', 'al', 'que', 'quien', 'quienes', 'cual', 'cuales',
  'como', 'donde', 'cuando', 'porque', 'es', 'son', 'fue', 'era',
  'ser', 'estar', 'hay', 'habla', 'hablan', 'trata', 'tratan', 'dime',
  'cuentame', 'muestra', 'favor', 'este', 'esta', 'estos', 'estas',
  'mi', 'tu', 'su', 'nuestro', 'me', 'te', 'se', 'nos',
};
```

#### C. Bilingual Domain Synonym Stem Expansion
Map Spanish and English user query stems to the canonical vocabulary in `agenda.json`:
| Query Term / Stem | Expanded Search Tokens |
| :--- | :--- |
| `charla`, `charlas`, `platica`, `platicas`, `sesion`, `sesiones` | `talk`, `session` |
| `ia`, `inteligencia artificial` | `ai`, `llm`, `model`, `inference`, `on-device` |
| `ponente`, `ponentes`, `expositor`, `expositores`, `conferencista`, `conferencistas` | `speaker`, `speakers` |
| `horario`, `horarios`, `agenda`, `evento`, `conferencia`, `cronograma`, `programa` | `schedule`, `agenda`, `day`, `conference` |
| `cuantizacion`, `cuantizar` | `quantization`, `quantize`, `int4`, `int8` |
| `rendimiento`, `velocidad`, `latencia` | `latency`, `performance`, `speed`, `memory` |
| `movil`, `celular`, `dispositivo` | `mobile`, `edge`, `phone`, `device` |

#### D. General Query Detection & Representative Keynote Fallback
Define broad overview query keywords:
```dart
static const Set<String> _generalQueryKeywords = {
  'agenda', 'charla', 'charlas', 'talk', 'talks', 'conferencia',
  'conference', 'evento', 'event', 'resumen', 'overview', 'summary',
  'sesion', 'sesiones', 'session', 'sessions', 'horario', 'schedule',
  'cronograma', 'programa', 'todo', 'todas',
};
```

**Fallback Rule**:
If:
1. The normalized query contains any general overview keyword, OR
2. Specific keyword scoring yields zero matches across all talks,

Then, instead of returning an empty list `[]`, return the **4 representative keynote talks across all tracks and days**:
- `talk-001`: *On-Device LLMs: Why the Edge Is Eating the Cloud* (Day 1, Engineering)
- `talk-006`: *Designing Trust: UI Patterns for Grounded AI Answers* (Day 1, Product & Design)
- `talk-011`: *Riverpod at Scale: Composition Roots and Testable Boundaries* (Day 2, Engineering)
- `talk-016`: *The Economics of Local Inference: Total Cost of Ownership* (Day 2, Product & Design)

This ensures the user interface always presents meaningful `CitationChip`s for discovery, and the model always has anchored context.

---

### 2. Language-Aware Grounded Prompt Contract (`BuildChatPromptUseCase`)

Refactor `BuildChatPromptUseCase` in `lib/domain/use_cases/build_chat_prompt_use_case.dart` with explicit persona grounding, dynamic language matching, and complete conference knowledge:

```text
You are Event LLM-Wiki, the official on-device AI guide for the On-Device AI Conference 2026.

RULES:
1. LANGUAGE: Detect the language of the user's question and respond in that EXACT same language (e.g. if the user asks in Spanish, answer in Spanish; if in English, answer in English).
2. KNOWLEDGE BASE: Ground your answers strictly in the conference agenda provided below. Do not make up talks or details not present in the agenda.
3. CITATIONS: When mentioning or recommending talks, explicitly mention the talk Title and Speaker name so attendees know where to go.
4. OVERVIEW: The conference spans 2 days (Day 1 & Day 2) with 2 simultaneous tracks: "Engineering" and "Product & Design", featuring 20 sessions in total.

CONFERENCE AGENDA:
[Structured list of retrieved talks or complete conference directory]

Question: {userQuestion}
Answer:
```

- When specific talks are retrieved via `RetrieveRelevantTalksUseCase`, they are formatted under `CONFERENCE TALKS (MOST RELEVANT)` with Title, Speakers, Day, Track, and Abstract.
- If the query was broad or generic, the prompt includes the baseline summary of the 4 keynotes and invite the attendee to ask about specific topics (e.g. quantization, Flutter, offline design, state management).
- Crucially, the negative instruction (*"Context: no matching talk was found... tell the user you couldn't find a talk"*) is **eliminated**. The model always receives sufficient agenda context to provide a helpful, grounded response.

---

### 3. Native Session Management in `LitertLmService`

To resolve prompt compounding in `LitertLmServiceImpl`:

1. **System Instruction Pre-loading**:
   When `initialize()` or `_model.createChat()` is executed:
   ```dart
   _chat = await model.createChat(
     systemInstruction: _buildConferenceSystemInstruction(),
   );
   ```
   LiteRT-LM compiles the conference guide persona, language-matching directive, and conference overview into the KV cache once.
2. **Per-Turn Query Insulation**:
   In `sendMessageStream(prompt)`, `prompt` passed to `_chat.addQueryChunk(...)` contains only the turn-specific user query and dynamic retrieved talk context, avoiding repeated duplication of the static system instruction.
3. **Session Reset on Context Boundary**:
   If the conversation context exceeds budget or when the user initiates a clear-chat action, `_chat?.close()` is called and a fresh `createChat()` session is created from `_model`.

---

## Consequences

### Positive
- **Instant Cross-Lingual Usability**: Spanish-speaking attendees can query the agenda naturally (*"¿De qué tratan las charlas?", "¿Quién habla de Flutter?"*) and receive fluent Spanish responses grounded in the English agenda.
- **Robust General Question Handling**: Broad queries no longer trigger confusing refusals or hallucinations.
- **Zero Hallucination UI**: Clickable `CitationChip`s are always grounded in real conference talks (`RetrievedTalk`), maintaining the pre-generation citation integrity established in ADR 0002.
- **Optimal On-Device Latency**: Avoids the 2x latency penalty and fragility of function calling on Gemma 3 1B.
- **Pure Dart Separation**: `RetrieveRelevantTalksUseCase` and `BuildChatPromptUseCase` remain 100% pure Dart, tested with exhaustive unit fixtures without requiring native engine mocks.

### Negative / Trade-offs
- The lexical scorer uses a handcrafted synonym dictionary rather than an embedding model. If novel terms appear outside the synonym map, retrieval relies on the keynote fallback. Given the small, fixed 20-talk corpus, this is a deliberate and accepted engineering trade-off.

---

## Compliance

`flutter-reviewer` must verify the following invariants:

1. **Pure Dart Domain Layer**:
   `RetrieveRelevantTalksUseCase` and `BuildChatPromptUseCase` must import only domain models and `dart:core` / `dart:collection`. No Flutter UI (`package:flutter/*`), no plugin imports, and no `dart:io`.
2. **Diacritic Invariant**:
   `RetrieveRelevantTalksUseCase` must normalize accented vowels (`á`, `é`, `í`, `ó`, `ú`, `ñ`) such that Spanish queries match English counterparts with diacritics removed.
3. **Non-Empty Retrieval Guarantee**:
   For any recognized general conference query or empty scored match, `RetrieveRelevantTalksUseCase` must return the 4 representative keynote talks (`talk-001`, `talk-006`, `talk-011`, `talk-016`) instead of an empty list `[]`.
4. **Deterministic UI Citations**:
   `ChatViewModel` must continue to construct `Citation` objects directly from `RetrieveRelevantTalksUseCase` results **before** inference streaming begins. Citations must never be parsed from the model's generated text stream.
5. **No Native Leaks**:
   `LitertLmServiceImpl` must close and re-instantiate `InferenceChat` without leaking native sessions or memory across repeated chat interactions.

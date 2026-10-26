# 0001. LLM runtime & model: flutter_litert_lm + Gemma3-1B-IT (dynamic_int4)

- **Status**: accepted
- **Date**: 2026-09-22
- **Deciders**: flutter-architect

## Context

`event_llm_wiki` needs to answer free-text questions about a bundled
conference agenda via a chat interface, **fully offline** (no network call
at inference time — the only network use in this app at all is the one-time
model download, see `doc/adr/0005-model-download-flow.md`). That requires an
on-device LLM inference runtime and a model small enough to download and run
on a mid-range phone, Android-first (Android + iOS were both scaffolded by
`flutter create`, but see the iOS note below).

## Decision

Use **`flutter_litert_lm` (`^0.3.0`, resolved and confirmed against the
installed package's actual source — see "API surface confirmed" below)** as
the inference runtime, running **`litert-community/Gemma3-1B-IT`** in
`.litertlm` format, `dynamic_int4` quantization, ~529 MB, 4096-token
context. The model is downloaded at runtime, not bundled (see ADR 0005) —
`assets/agenda.json` is the only bundled app asset (see ADR 0002).

Gemma3-1B-IT was chosen over the smaller `Gemma3-270M` variant: the 270M
model targets narrow, fine-tuned single-task use (e.g. classification,
short extraction), not the open-ended conversational QA plus light
multi-turn follow-up this app's Chat tab needs. 1B-IT is the smallest
variant in the Gemma3 family with general-purpose instruction-following
quality adequate for grounded RAG question-answering.

`LiteLmBackend.cpu` is used explicitly (not GPU/NPU auto-detection): per the
installed package's platform support table, GPU/NPU are Android-only and
iOS is CPU (XNNPACK)-only, so defaulting to CPU keeps behavior uniform
across the one platform this app actually targets for inference (Android —
see the iOS note below) without a runtime backend-capability probe this
app's scope does not need. `flutter-implementer` may revisit this if
on-device checkpoint profiling (PLAN.md phase 8) shows CPU is materially too
slow on the target test device.

### API surface confirmed against the installed package (0.3.0)

The assumed API shape from the initial brief
(`LiteLmEngine.create(LiteLmEngineConfig(modelPath, backend))` →
`engine.createConversation()` → `conversation.sendMessageStream(text)`)
matches the real package almost exactly, confirmed by reading
`flutter_litert_lm-0.3.0`'s own `lib/src/engine.dart`,
`lib/src/conversation.dart`, `lib/src/config.dart`, `lib/src/backend.dart`,
`lib/src/message.dart`, and its `example/lib/chat_screen.dart` reference
usage (via `pub cache`, not just pub.dev's listing). Two details worth
recording explicitly because they are easy to get wrong:

- `sendMessageStream` returns `Stream<LiteLmMessage>`, not `Stream<String>`.
  Each `LiteLmMessage.text` is a **delta** (newly generated text since the
  last emission), not a cumulative snapshot of the response so far — the
  example app's own doc comment confirms this ("LiteRT-LM's Flow emits one
  Message per generated chunk, where the text is the NEW tokens only").
  `data/services/litert_lm_service.dart`'s `sendMessageStream` is the one
  seam that maps `Stream<LiteLmMessage>` → `Stream<String>`, preserving
  the same delta (append, don't overwrite) semantics — see
  `ChatEngineRepository.sendMessage`'s doc comment.
- `LiteLmEngineConfig`/`LiteLmConversationConfig` also expose
  `cacheDir`, `visionBackend`/`audioBackend`, `systemInstruction`,
  `samplerConfig`, and tool-calling (`LiteLmTool`,
  `automaticToolCalling`) — all out of scope for this app (no multimodal
  input, no tool calling; see PLAN.md's non-goals) and deliberately not
  wired into `ChatEngineRepository`'s narrow interface.

### iOS: explicit non-goal today, confirmed to require more than "a stub"

The installed package's README confirms iOS support is "Beta, CPU (XNNPACK)
only" — but more importantly, **the plugin ships no prebuilt iOS runtime by
default**: a one-time `bash scripts/build_ios_frameworks.sh` step (30-60
minutes) is required from the plugin's own checkout before `flutter build
ios` will even link, because Google's LiteRT-LM does not publish a prebuilt
iOS XCFramework the way it does for Android's `.aar`. This is a materially
higher bar than "an unimplemented stub" and is out of scope for this app
(see PLAN.md's non-goals: "working iOS inference today"). `flutter create`'s
iOS build files are left in place (Android + iOS were both scaffolded), so
a future pass can pick this up, but no engineering time is budgeted to it in
this plan, and PLAN.md's phase 12 on-device checklist records iOS as
explicitly unverified rather than silently skipped.

## Alternatives considered

- **`flutter_gemma` / MediaPipe LLM Inference API** — rejected: MediaPipe's
  GenAI task library is a heavier, more opinionated wrapper (built-in
  session/RAG scaffolding of its own) than this app needs given it already
  has a from-scratch lexical RAG pipeline (ADR 0002); `flutter_litert_lm`'s
  thinner `LiteLmEngine`/`LiteLmConversation` surface is a better fit for a
  single custom prompt-in, stream-out use case with no built-in retrieval
  step to fight with or route around.
- **llama.cpp / GGUF via a Dart FFI binding** — rejected: no actively
  maintained, plugin_platform_interface-based Flutter package wraps this
  cleanly today; building and maintaining a custom FFI binding is
  significant scope this small app does not justify, versus an existing
  plugin already exposing a conversation/streaming API.
- **A cloud LLM API (OpenAI/Anthropic/Gemini API, etc.)** — rejected
  outright: the entire point of this app is a fully offline, on-device
  assistant (see PLAN.md's context) — a cloud API would violate that
  requirement in the normal case, not just as a fallback.

## Consequences

- `package:flutter_litert_lm` is confined to exactly one file,
  `data/services/litert_lm_service.dart` — see
  `doc/adr/0003-state-management-riverpod.md`'s compliance rule and
  `domain/repositories/chat_engine_repository.dart`'s doc comment. No
  `Notifier`/use case/widget may import it.
  `data/repositories/chat_engine_repository_impl.dart` depends only on
  `LitertLmService`.
- `LitertLmService` is deliberately left untested (see its doc comment) —
  the real native engine, the real ~529 MB model, and real inference are
  the three things `flutter test` must never touch, per PLAN.md's testing
  constraint. Its correctness is verified at PLAN.md's on-device checkpoint
  B (phase 8), the most critical of the three checkpoints.
- Model choice (Gemma3-1B-IT, dynamic_int4, ~529 MB, 4096 ctx) is
  hard-coded as a single download URL in
  `data/repositories/model_download_repository_impl.dart`'s construction
  (wired in `main.dart`) — there is no in-app model picker (unlike this
  package's own example app), which is intentional: PLAN.md's non-goals
  exclude multi-model support.
- If on-device profiling shows Gemma3-1B-IT's latency/memory profile is
  unacceptable on the target test device , the
  next fallback in this same family is `Gemma3-270M` traded for
  significantly weaker open-ended QA quality — that tradeoff would need a
  new ADR, not a silent swap.

## Compliance

`flutter-reviewer` checks:
- `package:flutter_litert_lm` is imported only in
  `lib/data/services/litert_lm_service.dart`.
- No file under `lib/domain/**` or `lib/ui/**` imports
  `package:flutter_litert_lm`.
- `ChatEngineRepositoryImpl` depends on `LitertLmService`, never directly
  on `LiteLmEngine`/`LiteLmConversation`.
- Any change to the model URL/quantization/expected file size in
  `ModelDownloadRepositoryImpl` and `ValidateDownloadedModelUseCase` is
  accompanied by an update to this ADR's "Decision" section (model choice
  is a recorded architectural decision, not an incidental config value).

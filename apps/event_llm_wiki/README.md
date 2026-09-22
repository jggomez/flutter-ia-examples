# Event LLM-Wiki

A browsable conference-agenda wiki with an on-device chat assistant that
answers questions about the agenda using retrieval-augmented generation
(RAG), entirely offline, with citations back to the specific talks it used.

## Status

Architecture and implementation are complete: 119 tests passing,
`flutter analyze` clean, everything wired in `main.dart` except the
composition-root providers (which intentionally throw until overridden,
same pattern as `rps_live`). What remains is the on-device verification
pass — downloading the real ~529 MB model, running real inference, and
exercising the full UI on a physical Android device — which is blocked on
having a connected device.

## How it works

- **Inference**: `flutter_litert_lm` running
  `litert-community/Gemma3-1B-IT` (`.litertlm`, `dynamic_int4`,
  ~529 MB, 4096-token context), downloaded at runtime rather than bundled.
  See
  [`doc/adr/0001-llm-runtime-model-selection.md`](doc/adr/0001-llm-runtime-model-selection.md).
- **Retrieval**: no embeddings — a plain-Dart weighted lexical/keyword
  scorer over the bundled `assets/agenda.json` (title x3, speaker x2,
  track/day x1, abstract x1), returning the top 3 matching talks. See
  [`doc/adr/0002-rag-lexical-retrieval.md`](doc/adr/0002-rag-lexical-retrieval.md).
- **Chat**: a single conversation thread with token streaming. Citations
  are the retrieved talks computed before generation, not parsed out of the
  model's response, so they render immediately and are always accurate.
- **State management**: Riverpod, inherited from `rps_live`'s ADR with one
  documented exception (the chat view model is not `.autoDispose`, because
  the loaded model is expensive to reload and there is only one consumer).
  See
  [`doc/adr/0003-state-management-riverpod.md`](doc/adr/0003-state-management-riverpod.md).
- **Persistence**: Hive, for chat history only. See
  [`doc/adr/0004-persistence-hive-chat-history.md`](doc/adr/0004-persistence-hive-chat-history.md).
- **Model download**: one-shot, non-resumable, streamed to a temp file,
  size-validated, then atomically renamed. See
  [`doc/adr/0005-model-download-flow.md`](doc/adr/0005-model-download-flow.md).

## Architecture

Layered `domain` / `data` / `ui`, mirroring `rps_live`'s conventions. See
[`PLAN.md`](PLAN.md) for the full folder layout and the implementation
phase breakdown, including the three on-device checkpoints the plan
requires before this app is considered done.

## The gated model and the HuggingFace token

`litert-community/Gemma3-1B-IT` is gated behind Google's Gemma license: an
unauthenticated download returns HTTP 401. To run this app:

1. Accept the license at
   `https://huggingface.co/litert-community/Gemma3-1B-IT` (requires a
   HuggingFace account).
2. Generate a read-only access token under Settings -> Access Tokens.
3. Create `dart_defines.local.json` in this directory (already
   gitignored, never committed):
   ```json
   {"HF_TOKEN": "hf_your_token_here"}
   ```

`ModelDownloadServiceImpl` reads `HF_TOKEN` via `String.fromEnvironment`
and sends it as a `Bearer` token only when it is non-empty.

## Running

```bash
flutter pub get
flutter run --dart-define-from-file=dart_defines.local.json
```

The Agenda tab works immediately; the Chat tab shows a download screen
until the model finishes downloading and passes validation.

## Testing

```bash
flutter test
```

The automated suite never touches the real native engine, a real ~529 MB
download, or a real network call — `data/services/litert_lm_service.dart`
is the one deliberately untested pass-through wrapper around
`flutter_litert_lm`, exactly like `rps_live` isolates `camera`.

# 0005. Sequential Dual-Model Wi-Fi-Gated Download Flow: EmbeddingGemma 2 & Gemma 4 E2B IT

- **Status**: accepted (updated for Gemma 4 E2B IT ~2.58 GB payload)
- **Date**: 2026-10-24 (Updated: 2026-10-25)
- **Deciders**: flutter-architect

## Context

**StudyGemma** requires **two** `.litertlm` model artifacts on the device before RAG indexing and grounded chat can run (ADR 0001):
1. **Stage 1 — Embedding Model (`EmbeddingGemma 2`)**:
   - File: `embeddinggemma-2-text-270m.litertlm` (~157.0 MB)
   - URL: `https://huggingface.co/litert-community/embeddinggemma-2-text-270m-litert-lm/resolve/9be6e8b90982095dc05c2bd162e4b954ee4dbac7/embeddinggemma-2-text-270m.litertlm` (public, ungated)
2. **Stage 2 — Generative Model (`Gemma 4 E2B IT`)**:
   - File: `gemma-4-E2B-it.litertlm` (~2.58 GB)
   - Upstream URL: `https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it.litertlm`

Combined, the initial setup transfers **~2.74 GB**. Downloading both models simultaneously would overwhelm device bandwidth, double peak socket/buffer memory pressure, and make progress reporting ambiguous. Moreover, HuggingFace's `resolve/` endpoints redirect (`302 Found`) to pre-signed CDN hosts (`us.aws.cdn.hf.co`, `cdn-lfs.huggingface.co`) that reject requests with HTTP `400`/`403` if an `Authorization: Bearer <token>` header is forwarded across hosts.

---

## Decision

### 1. Sequential Two-Stage Download State Machine
`ModelDownloadRepositoryImpl.downloadModelsStream({String? authToken})` orchestrates a sequential, stage-aware download pipeline yielding `ModelDownloadStatus` updates:
1. **Wi-Fi Pre-Flight Check**: Calls `NetworkConnectivityService.isWifiConnected()` (`MethodChannel('com.jggomez.flutterai.rag_study_gemma/network')` backed by Android `ConnectivityManager` `NetworkCapabilities.TRANSPORT_WIFI`). If Wi-Fi is inactive, immediately yields `ModelDownloadPhase.failed` with an actionable Wi-Fi required message before opening any HTTP connection.
2. **Stage 1 (`ModelDownloadPhase.downloadingEmbedding`)**:
   - Checks if the local `EmbeddingGemma 2` file already exists and passes `ValidateDownloadedModelsUseCase.isValidEmbeddingModel(sizeBytes)`.
   - If not ready, deletes any stale `embeddinggemma-2-text-270m.litertlm.part` file, streams the ~157 MB artifact to the `.part` file, validates its size against `ValidateDownloadedModelsUseCase.minEmbeddingModelSizeBytes` (`100 * 1024 * 1024` bytes / 100 MB), and atomically renames `.part` to the final path.
3. **Stage 2 (`ModelDownloadPhase.downloadingLlm`)**:
   - Checks if the local `Gemma 4 E2B IT` file already exists and passes `ValidateDownloadedModelsUseCase.isValidLlmModel(sizeBytes)`.
   - If not ready, deletes any stale `.part` file, streams the ~2.58 GB artifact to `.part`, validates its size against `ValidateDownloadedModelsUseCase.minLlmModelSizeBytes` (`400 * 1024 * 1024` bytes / 400 MB), and atomically renames `.part` to the final path.
4. **Completion (`ModelDownloadPhase.ready`)**: Emits `ModelDownloadPhase.ready` with `progress: 1.0` only when **both** files are validated and renamed into place on disk.

### 2. Optional HuggingFace Token & Build-Time `dart_defines.local.json` Support
- Users can enter an optional HuggingFace Access Token (`hf_...`) in `ModelDownloadScreen` or supply it at build/run time via `--dart-define-from-file=dart_defines.local.json` (`String.fromEnvironment('HF_TOKEN')`).
- `dart_defines.local.json` is gitignored so credentials are never committed to version control.

### 3. Manual Cross-Host CDN Redirect Resolution & Header Sanitization (`ModelDownloadService`)
- **Cross-Host `Authorization` Stripping**: `ModelDownloadService` sets `request.followRedirects = false` and resolves HTTP `301`/`302`/`303`/`307`/`308` redirects manually (up to 6 hops). The `Authorization: Bearer <token>` header is attached **only** when `currentUri.host == initialUri.host` (`huggingface.co`) and stripped automatically when following redirects to external CDN hosts (`us.aws.cdn.hf.co`, `cdn-lfs.huggingface.co`).
- **Ungated Mirror Fallback Support**: If the primary gated URL returns HTTP `401` or `403`, `ModelDownloadService` falls back to the configured fallback mirror URL without an `Authorization` header.

### 4. Stage-Level Skip on Retry (Without Partial-File Resume)
- Individual files are streamed to `<filename>.part` and never resumed mid-file (any leftover `.part` is deleted before downloading that stage).
- However, if Stage 1 (`EmbeddingGemma 2`, 157 MB) succeeded and was atomically renamed before a network drop occurred during Stage 2 (`Gemma 4 E2B IT`, 2.58 GB), retrying `downloadModelsStream` recognizes that Stage 1 is already valid on disk and proceeds directly to Stage 2—saving 157 MB of redundant transfer while keeping each file atomic.

---

## Consequences

- **Zero Corrupt Partial States**: Neither model is visible to `checkModelsReady()` until its `.part` stream finishes, passes minimum-size validation, and completes an OS-level atomic rename.
- **Cellular Protection**: No 2.74 GB download can be initiated accidentally over mobile cellular data.
- **No Raw Secrets in Code**: `HF_TOKEN` is read exclusively from runtime user input or `String.fromEnvironment('HF_TOKEN')`.

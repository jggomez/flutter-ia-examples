# ADR 0002: Native Wi-Fi `MethodChannel` & Atomic Model Download Pipeline

- **Status**: Accepted
- **Date**: 2026-10-25
- **Scope**: `apps/adk_pocket_squad` (`android/app/src/main/kotlin/.../MainActivity.kt`, `lib/data/services/network_connectivity_service.dart`, `lib/data/services/model_download_service.dart`)

## Context & Problem Statement

The default on-device model (`gemma-4-E2B-it.litertlm`, `litert-community/gemma-4-E2B-it-litert-lm`) is a **2.58 GB** binary artifact downloaded onto the user's Android device at runtime (or pre-staged in `<appSupportDir>/models/gemma-4-E2B-it.litertlm`). Downloading 2.58 GB over cellular data without explicit warning or corrupting the model file on interrupted transfers would degrade user trust and cause native FFI crashes during `mmap` initialization. Additionally, Hugging Face redirects gated/LFS model URLs from `huggingface.co` to cross-host CDN domains (`cdn-lfs.huggingface.co` / `us.aws.cdn.hf.co`), which reject requests with `400`/`401` if the `Authorization: Bearer <hf_token>` header is forwarded across hosts.

## Decision

### 1. Native Android Wi-Fi `MethodChannel` (`com.jggomez.flutterai.adk_pocket_squad/network`)
- **`MainActivity.kt`**:
  - Registers `MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.jggomez.flutterai.adk_pocket_squad/network")`.
  - Handles `"isOnWifi"` by querying Android's `ConnectivityManager` (`getNetworkCapabilities(activeNetwork)?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true`).
- **`NetworkConnectivityService` (`lib/data/services/network_connectivity_service.dart`)**:
  - Wraps the platform channel with safe fallback handling (`PlatformException` / test environment fallback) and gates both the 2.58 GB model download and LAN Ollama reachability checks.

### 2. Cross-Host Redirect Sanitization & Atomic `.part` Download (`ModelDownloadService`)
- **Target Path**: `<getApplicationSupportDirectory()>/models/gemma-4-E2B-it.litertlm`.
- **Fast-Path Readiness Verification**:
  - On app launch, `ModelDownloadService.isModelDownloaded()` checks if `gemma-4-E2B-it.litertlm` exists and has `lengthSync() >= 400 * 1024 * 1024` (`>= 400 MB`). If already present on disk, the app bypasses download and transitions straight into `PocketSquadWorkspaceScreen`.
- **Manual Redirect Resolution**:
  - Sets `request.followRedirects = false` up to 8 hops.
  - Attaches `Authorization: Bearer <token>` ONLY when the request host matches `huggingface.co` (`_isSameOriginHost`), stripping `Authorization` on cross-host CDN redirects (`cdn-lfs.huggingface.co`, `*.hf.co`).
  - Supports primary URL (`https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it.litertlm`) and public ungated mirror fallback.
- **Atomic `.part` Stream & Validation**:
  - Streams bytes into `gemma-4-E2B-it.litertlm.part`, emitting progress (`downloadedBytes`, `totalBytes`, `progress` `0.0..1.0`).
  - Verifies final `.part` file size `>= 400 MB` before atomically renaming `.part` to `gemma-4-E2B-it.litertlm`. Deletes `.part` on cancellation or error.

## Consequences & Reviewer Compliance Rules

- **Positive**: Zero corrupt partial models mapped by LiteRT-LM FFI; safe Wi-Fi enforcement; seamless Hugging Face CDN redirect handling.
- **Compliance Rules for `flutter-reviewer`**:
  1. `MainActivity.kt` MUST register `com.jggomez.flutterai.adk_pocket_squad/network` and `AndroidManifest.xml` MUST declare `INTERNET` and `ACCESS_NETWORK_STATE` with `minSdk = 26`.
  2. `ModelDownloadService` MUST write to `.part`, strip `Authorization` on cross-host redirects, verify minimum byte size (`>= 400 MB`), and atomically rename on completion.

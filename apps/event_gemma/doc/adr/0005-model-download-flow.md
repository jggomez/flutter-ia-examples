# 0005. Model download flow: one-shot, non-resumable, size-checked, atomic rename

- **Status**: accepted
- **Date**: 2026-09-22
- **Deciders**: flutter-architect

## Context

The ~529 MB `Gemma3-1B-IT` `.litertlm` file (ADR 0001) is not bundled with
the app — it must be downloaded at runtime, lazily, the first time the user
opens the Chat tab. This is a large download over a real (potentially
conference-venue, potentially flaky) network connection, so the flow must
handle: a user backgrounding the app mid-download, a force-quit mid-download
followed by relaunch, and a corrupted/truncated file — without ever leaving
the app in a state where it thinks a broken file is a valid model.

## Decision

**One-shot, non-resumable download, with a min-size sanity check and an
atomic rename**, orchestrated by `ModelDownloadRepositoryImpl`
(`domain/repositories/model_download_repository.dart`):

1. **Trigger**: lazy — starts only when the user opens the Chat tab and
   `ModelDownloadViewModel.startDownload()` is called from
   `ModelSetupScreen`'s call-to-action (never eagerly at app launch — see
   `main.dart`'s "sync Hive bootstrap only" doc comment).
2. **Source of truth**: local file existence, not a persisted flag — see
   `doc/adr/0004-persistence-hive-chat-history.md`'s "Model-download
   progress is NOT persisted" section.
3. **Stream to a `.part` file**: `ModelDownloadService.download(modelUrl)`
   streams the HTTP response body in chunks (`package:http`'s streamed
   request API, not a buffered `http.get`, so the ~529 MB body is never
   held fully in memory); `ModelDownloadRepositoryImpl` writes chunks to
   `AppStorageService.modelPartFilePath` as they arrive, emitting a
   `ModelDownloadStatus(phase: downloading, bytesDownloaded: ..., totalBytes:
   ...)` per chunk so `ModelSetupScreen` can render live progress.
4. **Not resumable**: any pre-existing `.part` file is deleted before a
   fresh download starts — both when the user explicitly retries after a
   failure, and implicitly on a fresh app launch if `checkLocalStatus()`
   finds a leftover `.part` with no matching valid model file (this is how
   a force-quit-mid-download is handled: the stale `.part` is simply
   discarded on next attempt, never resumed or trusted).
5. **Validate**: once the stream completes, `ValidateDownloadedModelUseCase`
   checks the `.part` file's size against a minimum-plausible-size
   threshold (well below the real ~529 MB, to allow for legitimate
   quantization-variant size differences, but well above a
   dropped-connection truncation).
6. **Atomic rename**: on a passing validation,
   `AppStorageService.renamePartFileToModelFile()` renames `.part` into
   place at the final model path — this is the single moment
   `checkLocalStatus()` will ever report `ModelDownloadPhase.ready`. A file
   mid-rename is never observable as "ready" by another reader (an OS-level
   rename is atomic on both Android and iOS's local filesystems).
7. **Failure surfaces as a status, not a thrown exception**: `download()`'s
   stream never throws — a network error or a failed validation both emit a
   terminal `ModelDownloadPhase.failed` event with `errorMessage` set, so
   `ModelSetupScreen` has one `.when(data: ...)` path to render, including
   the failure state and its retry CTA.

## Alternatives considered

- **Range-header resume** (persisting `bytesDownloaded` and re-requesting
  with an HTTP `Range` header on retry) — rejected: real resumability needs
  either a stable, verifiable partial-content checksum or trusting an
  untrusted partial file at face value; for a one-time ~529 MB download
  that is expected to succeed on a reasonable connection, the engineering
  cost of a correct resume implementation (handling a server that doesn't
  honor `Range`, a `.part` file whose partial bytes don't actually match
  what a fresh request would produce, etc.) was judged disproportionate to
  the benefit over "delete and restart cleanly," especially given this is a
  single-model, single-URL app with no multi-file/manifest complexity.
- **SHA-256 checksum verification** — rejected in favor of the cheaper
  min-size sanity check: a real checksum needs a trustworthy published hash
  to check against (HuggingFace's `resolve/main/` URLs do not provide one
  inline with the file download in a way this app conveniently consumes),
  and maintaining a hardcoded expected hash tightly couples this app to one
  exact upstream file revision, breaking silently if the hosted file is
  ever re-uploaded with a fix. A min-size check catches the actual failure
  mode this app cares about (a truncated/interrupted download) without that
  coupling; a full corruption-but-right-size download is accepted as a
  residual risk `ValidateDownloadedModelUseCase` does not attempt to close
  (a corrupt-but-right-size model would fail at
  `ChatEngineRepository.initialize()` instead, surfacing as
  `ModelLoadException` — a real, if less proactive, failure mode already
  handled).
- **A background-download plugin (e.g. `flutter_downloader`)** — rejected:
  those plugins exist primarily to keep a download alive when the app is
  backgrounded/killed by the OS, which is valuable for long-running
  transfers the user expects to complete unattended. This app's flow is
  explicitly foreground-only (the user is on `ModelSetupScreen` watching
  progress); PLAN.md's on-device checklist even requires backgrounding
  mid-download to be handled by simply discarding and letting the user
  retry, not resuming in the background. Adding a background-download
  plugin's platform-service/notification complexity for a flow that
  intentionally doesn't support backgrounding is not justified.

## Consequences

- A user with a slow or interrupted connection may need to restart the
  ~529 MB download from zero more than once — an accepted, documented
  tradeoff for implementation simplicity, not an oversight. If real-world
  usage shows this is a frequent, painful problem, Range-header resume
  becomes the natural next ADR to write (superseding this one's "not
  resumable" decision), not a silent patch.
- `ModelDownloadService`/`AppStorageService` are the only two collaborators
  `ModelDownloadRepositoryImpl` depends on — both fakeable in tests (a
  `FakeModelDownloadService` emitting canned `ModelDownloadChunk`s including
  a simulated mid-stream failure, and a `FakeAppStorageService` backed by a
  temp directory or in-memory map), so `flutter test` never makes a real
  network call or touches real device storage, per PLAN.md's testing
  constraint. PLAN.md's on-device checkpoint A (phase 7) is where the real
  ~529 MB download is exercised, once, against the connected Android
  device .
- `ValidateDownloadedModelUseCase.minValidSizeBytes` is a single named
  constant `flutter-implementer` must set deliberately (see that class's
  doc comment) — not copy-pasted from an unrelated size assumption.

## Addendum (2026-10-21): On-device Wi-Fi connectivity check & user confirmation gate

To prevent accidental cellular data consumption on a ~529 MB transfer and ensure the model is downloaded strictly on the mobile device with explicit user consent:

1. **Strictly On-Device Download**:
   - The ~529 MB `Gemma3-1B-IT` `.litertlm` model is never downloaded on the host PC or bundled into the application binary. It is downloaded strictly on-demand onto the mobile device's `getApplicationSupportDirectory()` via `AppStorageService`.
2. **Wi-Fi Connectivity Gate (`NetworkConnectivityService`)**:
   - Introduce `NetworkConnectivityService` (`lib/data/services/network_connectivity_service.dart`) exposing `Future<bool> isWifiConnected()`, backed by a lightweight `MethodChannel('com.jggomez.flutterai.event_llm_wiki/connectivity')` that queries Android's `ConnectivityManager` (`NetworkCapabilities.TRANSPORT_WIFI`) in `MainActivity.kt` (paired with `android.permission.INTERNET` and `android.permission.ACCESS_NETWORK_STATE` in `android/app/src/main/AndroidManifest.xml`).
   - `ModelDownloadRepository` exposes `Future<bool> isWifiConnected()` and `Stream<ModelDownloadStatus> download({String? authToken})`.
   - `ModelDownloadRepositoryImpl.download({String? authToken})` verifies `await _networkConnectivityService.isWifiConnected()` before opening the HTTP stream; if Wi-Fi is not active, it immediately yields `ModelDownloadStatus(phase: ModelDownloadPhase.failed, errorMessage: ...)` without initiating any network transfer.
3. **Explicit User Confirmation Dialog on `ModelSetupScreen`**:
   - Before calling `ModelDownloadViewModel.startDownload({String? authToken})`, `ModelSetupScreen` queries `isWifiConnected()` and presents a confirmation `AlertDialog` (`ValueKey('confirmModelDownloadDialog')`) displaying:
     - The model size (~529 MB) and on-device storage notice.
     - Active Wi-Fi connectivity status (disabling confirmation when Wi-Fi is disconnected).
     - An optional `HF_TOKEN` text field (used as `Bearer` token when `--dart-define=HF_TOKEN=...` is empty at build time, since `litert-community/Gemma3-1B-IT` is gated on HuggingFace).
     - Explicit `Cancel` (`ValueKey('cancelDownloadDialogButton')`) and `Download on Wi-Fi` (`ValueKey('confirmDownloadDialogButton')`) actions.
4. **HuggingFace Cross-Host Redirect Header Stripping & Ungated Mirror Fallback (`ModelDownloadServiceImpl`)**:
   - HuggingFace `resolve/main/` endpoints respond with an HTTP `302 Found` redirect to a pre-signed CDN URL (`us.aws.cdn.hf.co` / `cdn-lfs.huggingface.co`). When `package:http` auto-follows redirects (`followRedirects = true`), it forwards the `Authorization: Bearer <token>` header to the pre-signed CDN host, which rejects the request (`400`/`403`) because pre-signed query parameters conflict with an `Authorization` header.
   - `ModelDownloadServiceImpl` therefore resolves redirects manually (`request.followRedirects = false`, up to 6 hops), attaching `Authorization: Bearer <token>` **only** when `currentUri.host == initialUri.host` (`huggingface.co`) and omitting it on cross-host CDN hops.
   - Furthermore, if the primary gated URL (`litert-community/Gemma3-1B-IT`) returns HTTP `401` or `403` (for example, when the user's HuggingFace account has not accepted the gated repository license or no token was entered), `ModelDownloadServiceImpl` automatically falls back to the public ungated `Gemma3-1B-IT` int4 `.litertlm` mirror (`https://huggingface.co/lotapa/gemma3-1b-it-int4.litertlm/resolve/main/gemma3-1b-it-int4.litertlm`) without an `Authorization` header.

## Compliance

`flutter-reviewer` checks:
- No persisted "download complete"/"model ready" flag anywhere (Hive,
  `shared_preferences`, or otherwise) — `checkLocalStatus()` must stay
  filesystem-derived (cross-checked with `doc/adr/0004-persistence-hive-chat-history.md`'s
  compliance rule).
- `ModelDownloadRepositoryImpl.download()` always verifies
  `NetworkConnectivityService.isWifiConnected()` before opening the HTTP
  stream and deletes any pre-existing `.part` file before writing a new one
  (no silent resume).
- `ModelSetupScreen` always requires explicit user confirmation via the
  confirmation dialog (`ValueKey('confirmModelDownloadDialog')`) before
  invoking `startDownload()`.
- `ModelDownloadRepositoryImpl.download()`'s returned `Stream` never lets
  an exception propagate uncaught to its subscriber — every failure path
  (including missing Wi-Fi) ends in a `ModelDownloadPhase.failed` event.
- No `package:flutter_downloader` (or equivalent background-download
  plugin) import anywhere under `lib/` without a new ADR superseding this
  one.
- Model file writes/renames only happen through `AppStorageService` — no
  `dart:io` `File`/`Directory` usage scattered outside
  `data/services/app_storage_service.dart`.


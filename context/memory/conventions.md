# Conventions & Preferences (living — update in place)

## Stack
- **Flutter**: Dart SDK `^3.13.2`; `flutter_lints ^6.0.0`; analyzer excludes `build/`, `android/`, `ios/`. Riverpod 3.x manual providers (no codegen); Hive 2.x; `genui ^0.10.4` + `genui_a2a ^0.10.1` for A2UI v0.9 surfaces.
- **Python ADK Agents**: Scaffold via `agents-cli scaffold create <name> --agent adk --deployment-target cloud_run --prototype` (`google-agents-cli ~= 1.11.0`). Preserve `agents-cli-manifest.yaml`, `app/fast_api_app.py`, `app/app_utils/a2a.py`, `MODEL = "gemini-3.8-flash"`, `root_agent`, and `app = App(root_agent=root_agent, name="app")`.
- **ADK Tool Rules (`/google-agents-cli-adk-code`)**: Mandatory type hints, **zero default parameter values**, docstrings without mentioning `tool_context`, `tool_context: ToolContext` as final parameter, and JSON-serializable `dict` returns.
- **ADK Testing & Eval (`/google-agents-cli-eval`)**: Unit tests in `tests/unit/` only test deterministic Python tools, catalog schemas, and part converters (`uv run pytest`); agent behavioral evaluation uses `agents-cli eval run` (`tests/eval/`).

## Code
- English only for code, comments, commits, docs (user rule). SOLID / DRY / KISS, small single-purpose functions.
- Layer rule: `ui` → `domain` ← `data`; UI never imports `data` directly except via the composition root.
- File naming: `*_use_case.dart`, `*_repository.dart` (interface) / `*_repository_impl.dart`, `*_service.dart`, `*_dto.dart`, `*_view_model.dart`, `*_screen.dart`.
- Tests mirror `lib/` paths; fakes in `test/support/fakes.dart`; widget tests via `ProviderScope(overrides: [...])`.
- Always `.dispose()` controllers/subscriptions; `if (!mounted) return;` after `await` before `BuildContext`.

## Secrets & config
- Local secrets via `--dart-define-from-file=dart_defines.local.json`; `**/*.local.json` is gitignored. Never commit tokens.
- Large model weights (`*.litertlm`, `*.task`, `*.gguf`) are gitignored and downloaded at runtime.

## Process (`senior-dev-flutter` & `senior-dev` 6-state DAG)
- Orchestrator never edits Dart or Python source code; delegates Flutter tracks to `flutter-architect` / `flutter-implementer` / `flutter-reviewer` / `flutter-release-engineer` and backend/Python tracks to `code-implementer` / `qa-tester` / `compliance-verifier`.
- `PLAN.md` (per app) with triage table before any code change; ADRs in `apps/<app>/doc/adr/NNNN-*.md`.
- Update `context/memory/` only at State 5 or on explicit handoff; keep `MEMORY.md` ≤ 100 lines.
- User communicates in Spanish; artifacts/code stay in English.

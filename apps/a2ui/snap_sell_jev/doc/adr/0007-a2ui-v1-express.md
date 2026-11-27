# 0007. Migrate to A2UI 1.0, `a2ui_flutter` and A2UI Express

- **Status**: accepted (supersedes the v0.9 parts of 0001, 0003, 0004)
- **Date**: 2026-11-21

## Context
A2UI 1.0 shipped in Nov 2026. `genui`/`genui_a2a` are deprecated in favour of
`a2ui_flutter` 0.4 + `a2ui_core` 0.8. The Python `a2ui-agent-sdk` 0.12 makes
**A2UI Express** the default inference format: the model writes a compact DSL
inside `<a2ui>…</a2ui>` and the SDK compiles it to v1.0 JSON. The v0.9 app
(`apps/a2ui/snap_sell`) stays untouched as a reference.

## Decision
1. **Separate inference format from wire format.** The model writes Express;
   `A2uiGenerator(..., inference_format_factory=ExpressFormatFactory())`
   compiles and validates it server-side. The renderer only ever sees JSON.
   The Express prompt for this catalog is ~35 k chars vs ~70 k for Direct JSON.
2. **One contract, generated.** `contracts/tools/migrate_to_v1.py` builds the
   v1.0 catalog (Basic subset + 5 custom components, `instructions`,
   `allowedParents`, `functions` map), the 1.0 examples, the agent's copy and
   the Dart constant `snap_sell_contract.g.dart`. Flutter component schemas and
   composition rules are read from that constant, so they cannot drift.
3. **Keep A2A.** No maintained Dart A2A client exists without `genui`, so the
   app ships a ~200-line JSON-RPC `message/stream` SSE client
   (`data/services/a2a_client.dart`) speaking the A2A v0.3 shape.
4. **One `MessageProcessor` with unified outbound.** Actions go to the view
   model; `callAgentFunction` goes to the agent and its
   `agentFunctionResponse` is fed back; render `error`s go back to the agent
   once per turn so it can fix the surface.
5. **Deterministic agent function.** `priceFeedback` is declared in the
   catalog, bound with `AgentFunction.from_api` and answered by
   `RendererToAgentMessageProcessor` in `SnapSellA2uiExecutor` without an LLM
   turn. The Flutter catalog omits it on purpose so the call is routed out.
6. **Self-repair.** `after_model_callback` parses the `<a2ui>` block; on
   `A2uiError` it returns a synthetic `a2ui_report_compile_error` call so the
   model retries once. If it still fails, only the prose is sent.
7. **Surface replacement.** v1.0 rejects re-creating a surface id, and the
   agent re-sends whole stages, so the renderer deletes the old one first.

## Consequences
- ✅ Fewer prompt tokens; malformed UI never reaches the device.
- ✅ Instant price feedback while dragging the slider, no LLM round-trip.
- ✅ Composition rules and `@checks` enforced identically on both sides.
- ⚠️ Express grammar is still a proposal; pinning `a2ui-agent-sdk>=0.12`.
- ⚠️ We own the A2A client (tests in `test/data/a2ui_agent_service_test.dart`).
- ⚠️ `a2ui-adk` is not used; ADK ↔ A2A conversion stays in `app/app_utils/a2a.py`.

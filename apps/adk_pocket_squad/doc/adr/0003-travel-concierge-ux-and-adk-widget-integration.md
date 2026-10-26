# ADR 0003: Editorial Luxury Travel Concierge UX & `flutter_adk` Widget Integration

- **Status**: Accepted
- **Date**: 2026-10-25
- **Scope**: `apps/adk_pocket_squad` (`lib/ui/theme/`, `lib/ui/providers/`, `lib/ui/view_models/`, `lib/ui/screens/`, `lib/ui/widgets/`)

## Context & Problem Statement

A multi-agent travel concierge powered by 3 sequential agents (`ScoutAgent` → `BudgetAuditorAgent` → `ConciergeAgent`) and real `FunctionTool` invocations (`calculate_budget_math`, `save_trip_plan`) requires a cohesive, responsive Material 3 interface that surfaces agent handoffs, tool calls, shared `session.state` artifacts, and persisted trips without frame drops (60/120fps budget) or memory leaks.

## Decision

### 1. Editorial Luxury Travel Concierge Design System (`lib/ui/theme/pocket_squad_theme.dart`)
- **Palette ("Horizon Obsidian & Sunset Amber/Teal")**:
  - Deep Obsidian night sky surfaces (`#0B101E` / `#131B2E`), Sunset Amber primary accent (`#F59E0B`), Tropical Teal secondary accent (`#14B8A6`), and semantic agent accent badges:
    - **Scout Agent (`scout_agent`)**: Compass Cyan (`#06B6D4`)
    - **Budget Auditor (`budget_auditor_agent`)**: Emerald Audit (`#10B981`)
    - **Concierge (`concierge_agent`)**: Royal Amber (`#F59E0B`)
- Supports both Dark (default) and Light Material 3 `ColorScheme` themes.

### 2. State Management & Lifecycle (`flutter_riverpod ^3.0.3` + `AdkChatController`)
- **Primary State Solution**: `flutter_riverpod` (`^3.0.3`) with composition root in `lib/ui/providers/app_providers.dart` combined with `ChangeNotifier`-based `ModelDownloadViewModel` and `PocketSquadViewModel` (following `flutter-apply-architecture-best-practices`).
- **`PocketSquadViewModel` (`lib/ui/view_models/pocket_squad_view_model.dart`)**:
  - Owns and disposes the active `AdkChatController`, tracks real-time 3-step `AdkWorkflowStep` progress (`scout_agent`, `budget_auditor_agent`, `concierge_agent`), synchronizes live `session.state` keys (`itinerary_draft`, `budget_audit`, `final_concierge_brief`), manages the `SavedTrip` vault list, and handles runtime switching between **On-Device Gemma 4 E2B (LiteRT-LM)** and **Local LAN Ollama (`LiteLlm`)**.

### 3. Four-Tab `PocketSquadWorkspaceScreen` (`lib/ui/screens/pocket_squad_workspace_screen.dart`)
1. **Tab 1 — Squad Mission (`MissionChatTab`)**:
   - Top live 3-agent pipeline status banner combining `AdkAgentHierarchyBadge` and `AdkWorkflowProgressIndicator`.
   - Horizontal quick-launch destination mission cards (*Kyoto 4 Days $1,200*, *Cartagena 3 Days $750*, *Lisbon 5 Days $1,500*, *Reykjavik 4 Days $1,800*).
   - Embedded `AdkChatView` with custom `messageBubbleBuilder` (showing which specialist agent authored each response) and `toolCallBuilder` (`AdkToolCallCard` highlighting `calculate_budget_math` and `save_trip_plan` executions).
2. **Tab 2 — Live Pipeline & State (`PipelineInspectorTab`)**:
   - Visual `SequentialAgent` DAG rendered with `AdkWorkflowGraphView`.
   - Live `session.state` artifact cards for `itinerary_draft`, `budget_audit`, and `final_concierge_brief`.
   - Embedded `AdkToolInspectorView` inspecting every `FunctionTool` call and JSON return payload.
3. **Tab 3 — Saved Trips Vault (`SavedTripsVaultTab`)**:
   - Displays persisted `SavedTrip` cards created by `ConciergeAgent`'s `save_trip_plan` tool (or manual demo/vault actions), complete with destination header, days badge, budget status pill (`WITHIN BUDGET` / `OVER BUDGET`), itemized USD & local currency breakdown, and expandable brief + packing checklist.
4. **Tab 4 — ADK Studio (`AdkDevStudioView`)**:
   - Embeds `flutter_adk`'s turnkey 4-tab developer IDE (`Chat`, `Workflow`, `Tools`, `Events`) bound to the live `AdkChatController`.

## Consequences & Reviewer Compliance Rules

- **Positive**: Showcases the full `flutter_adk` widget catalog (`AdkChatView`, `AdkWorkflowProgressIndicator`, `AdkWorkflowGraphView`, `AdkAgentHierarchyBadge`, `AdkToolCallCard`, `AdkToolInspectorView`, `AdkDevStudioView`) alongside a bespoke luxury travel concierge experience.
- **Compliance Rules for `flutter-reviewer`**:
  1. All `TextEditingController`, `ScrollController`, and `AdkChatController` instances MUST be disposed in `dispose()`.
  2. Async callbacks touching `BuildContext` MUST guard with `if (!context.mounted) return;`.
  3. Interactive custom cards and action buttons MUST expose clear labels/tooltips for accessibility and widget tests.

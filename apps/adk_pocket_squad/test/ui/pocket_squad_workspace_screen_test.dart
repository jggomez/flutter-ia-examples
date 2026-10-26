import 'package:adk_pocket_squad/data/llm/litert_chat_driver.dart';
import 'package:adk_pocket_squad/data/services/app_storage_service.dart';
import 'package:adk_pocket_squad/data/services/model_download_service.dart';
import 'package:adk_pocket_squad/data/services/network_connectivity_service.dart';
import 'package:adk_pocket_squad/domain/models/llm_engine_config.dart';
import 'package:adk_pocket_squad/main.dart';
import 'package:adk_pocket_squad/ui/providers/app_providers.dart';
import 'package:adk_pocket_squad/ui/screens/model_download_screen.dart';
import 'package:adk_pocket_squad/ui/screens/pocket_squad_workspace_screen.dart';
import 'package:adk_pocket_squad/ui/widgets/flutter_adk_widgets.dart';
import 'package:adk_pocket_squad/ui/widgets/formatted_agent_message_view.dart';
import 'package:adk_pocket_squad/ui/widgets/pocket_squad_adk_studio_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeWifiService implements NetworkConnectivityService {
  _FakeWifiService({this.wifiConnected = true});

  bool wifiConnected;

  @override
  Future<bool> isWifiConnected() async => wifiConnected;
}

class _FakeModelDownloadService extends ModelDownloadService {
  _FakeModelDownloadService({this.existingPath});

  String? existingPath;

  @override
  Future<String?> findExistingModelPath({int? minBytes}) async => existingPath;

  @override
  Future<String> resolveModelFilePath({int? minBytes}) async =>
      existingPath ?? '/tmp/${ModelDownloadService.modelFileName}';
}

void main() {
  late SharedPreferences sharedPreferences;
  late AppStorageService storageService;
  late FakeLiteRtChatDriver fakeDriver;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    sharedPreferences = await SharedPreferences.getInstance();
    storageService = AppStorageService(sharedPreferences: sharedPreferences);
    fakeDriver = FakeLiteRtChatDriver();
  });

  tearDown(() async {
    await fakeDriver.dispose();
  });

  testWidgets(
    'ModelDownloadScreen shows Wi-Fi Required gate when Wi-Fi is off and model is missing',
    (WidgetTester tester) async {
      final wifiService = _FakeWifiService(wifiConnected: false);
      final downloadService = _FakeModelDownloadService(existingPath: null);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(sharedPreferences),
            appStorageServiceProvider.overrideWithValue(storageService),
            networkConnectivityServiceProvider.overrideWithValue(wifiService),
            modelDownloadServiceProvider.overrideWithValue(downloadService),
            liteRtChatDriverProvider.overrideWithValue(fakeDriver),
          ],
          child: const PocketSquadApp(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ModelDownloadScreen), findsOneWidget);
      expect(find.textContaining('Gemma 4 E2B IT'), findsWidgets);
      expect(find.textContaining('Wi-Fi Required'), findsWidgets);
    },
  );

  testWidgets(
    'Conversational greeting ("Hola") replies via CoordinatorAgent with clean formatted text and populates ADK Studio Live Logger',
    (WidgetTester tester) async {
      final wifiService = _FakeWifiService(wifiConnected: true);
      final downloadService = _FakeModelDownloadService(
        existingPath: '/tmp/models/${ModelDownloadService.modelFileName}',
      );

      late ProviderContainer container;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(sharedPreferences),
            appStorageServiceProvider.overrideWithValue(storageService),
            networkConnectivityServiceProvider.overrideWithValue(wifiService),
            modelDownloadServiceProvider.overrideWithValue(downloadService),
            liteRtChatDriverProvider.overrideWithValue(fakeDriver),
          ],
          child: Builder(
            builder: (context) {
              container = ProviderScope.containerOf(context);
              return const PocketSquadApp();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(PocketSquadWorkspaceScreen), findsOneWidget);

      // Verify suggestion bubbles above the main textbox are removed
      expect(find.byType(AdkPromptSuggestionsBar), findsNothing);

      // Verify 4-step pipeline is rendered in header
      expect(find.text('0. Coordinator'), findsOneWidget);
      expect(find.text('1. ScoutAgent'), findsOneWidget);
      expect(find.text('2. BudgetAuditor'), findsOneWidget);
      expect(find.text('3. Concierge'), findsOneWidget);

      // Enter conversational greeting "Hola"
      await tester.enterText(
        find.byKey(const Key('mission_prompt_text_field')),
        'Hola',
      );
      await tester.tap(find.byKey(const Key('send_mission_prompt_button')));
      await tester.pumpAndSettle();

      // Verify Coordinator replied conversationally while 3 specialist steps remain pending
      final viewModel = container.read(pocketSquadViewModelProvider);
      final stepsById = {
        for (final step in viewModel.workflowSteps) step.id: step.status,
      };
      expect(stepsById['coordinator_agent'], AdkStepStatus.completed);
      expect(stepsById['scout_agent'], AdkStepStatus.pending);
      expect(stepsById['budget_auditor_agent'], AdkStepStatus.pending);
      expect(stepsById['concierge_agent'], AdkStepStatus.pending);

      // Verify FormattedAgentMessageView renders clean text without raw '###'
      expect(find.byType(FormattedAgentMessageView), findsWidgets);
      expect(find.textContaining('###'), findsNothing);
      expect(find.text('Coordinator • Intake'), findsWidgets);

      // Switch to ADK Studio -> Live Logger and verify live logs are populated
      await tester.tap(find.text('ADK Studio'));
      await tester.pumpAndSettle();

      expect(find.byType(PocketSquadAdkStudioTab), findsOneWidget);
      expect(find.byType(AdkAgentLoggerView), findsOneWidget);
      expect(viewModel.agentLogs, isNotEmpty);
      expect(find.text('No agent logs recorded yet.'), findsNothing);
      expect(find.text('User Prompt'), findsOneWidget);
    },
  );

  testWidgets(
    'Fast-path readiness transitions to PocketSquadWorkspaceScreen, hides tool calls in Squad Mission chat, and shows them in Pipeline & State + Trips Vault Final Result sheet + ADK Studio Live Logger',
    (WidgetTester tester) async {
      final wifiService = _FakeWifiService(wifiConnected: true);
      final downloadService = _FakeModelDownloadService(
        existingPath: '/tmp/models/${ModelDownloadService.modelFileName}',
      );

      late ProviderContainer container;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(sharedPreferences),
            appStorageServiceProvider.overrideWithValue(storageService),
            networkConnectivityServiceProvider.overrideWithValue(wifiService),
            modelDownloadServiceProvider.overrideWithValue(downloadService),
            liteRtChatDriverProvider.overrideWithValue(fakeDriver),
          ],
          child: Builder(
            builder: (context) {
              container = ProviderScope.containerOf(context);
              return const PocketSquadApp();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify fast-path transition to PocketSquadWorkspaceScreen
      expect(find.byType(PocketSquadWorkspaceScreen), findsOneWidget);
      expect(fakeDriver.isInitialized, isTrue);
      expect(find.text('Pocket Squad'), findsOneWidget);
      expect(find.byType(AdkPromptSuggestionsBar), findsNothing);
      expect(find.byType(AdkAgentHierarchyBadge), findsOneWidget);
      expect(find.byType(AdkWorkflowProgressIndicator), findsOneWidget);

      // Verify all 4 steps are rendered in SquadPipelineHeader
      expect(find.text('0. Coordinator'), findsOneWidget);
      expect(find.text('1. ScoutAgent'), findsOneWidget);
      expect(find.text('2. BudgetAuditor'), findsOneWidget);
      expect(find.text('3. Concierge'), findsOneWidget);

      // Verify preset cards are rendered in Tab 1 (Squad Mission) before conversation starts
      expect(find.text('Kyoto Cultural Odyssey'), findsOneWidget);

      // Tap the Kyoto preset card to launch the Coordinator -> 3-agent sequential mission
      await tester.tap(find.text('Kyoto Cultural Odyssey'));
      await tester.pumpAndSettle();

      // Verify all 4 workflow steps completed after transfer_to_agent -> pipeline execution
      final viewModel = container.read(pocketSquadViewModelProvider);
      for (final step in viewModel.workflowSteps) {
        expect(
          step.status,
          AdkStepStatus.completed,
          reason: 'Expected ${step.id} to be completed after preset mission',
        );
      }

      // Requirement 2 & 5: Verify Squad Mission chat hides AdkToolCallCard and renders
      // separate cards for ScoutAgent, BudgetAuditorAgent, and ConciergeAgent
      expect(find.byType(AdkChatView), findsOneWidget);
      expect(find.byType(AdkToolCallCard), findsNothing);
      expect(find.byType(FormattedAgentMessageView), findsWidgets);
      expect(find.textContaining('###'), findsNothing);
      expect(find.text('1 · Scout Agent · World Knowledge'), findsWidgets);
      expect(
        find.text('2 · Budget Auditor · Deterministic Math'),
        findsWidgets,
      );
      expect(find.text('3 · Executive Concierge · Trip Vault'), findsWidgets);

      // Verify each session artifact contains its isolated section
      expect(
        viewModel.sessionArtifacts['itinerary_draft'],
        isNot(contains('ConciergeAgent')),
      );
      expect(
        viewModel.sessionArtifacts['final_concierge_brief'],
        isNot(contains('ScoutAgent')),
      );

      // Switch to Tab 2: Pipeline & State -> verify tool calls ARE shown here!
      await tester.tap(find.text('Pipeline & State'));
      await tester.pumpAndSettle();

      expect(find.byType(AdkWorkflowGraphView), findsOneWidget);
      expect(find.byType(AdkToolCallCard), findsWidgets);
      expect(find.text('itinerary_draft'), findsWidgets);
      expect(find.text('budget_audit'), findsWidgets);
      expect(find.text('final_concierge_brief'), findsWidgets);
      expect(find.byType(AdkToolInspectorView), findsOneWidget);

      // Switch to Tab 3: Saved Trips Vault -> verify Final Result button and modal sheet
      await tester.tap(find.text('Trips Vault'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Kyoto'), findsWidgets);
      expect(find.textContaining('BUDGET'), findsWidgets);
      expect(find.text('View Final Result & Full Itinerary'), findsOneWidget);

      await tester.ensureVisible(
        find.text('View Final Result & Full Itinerary'),
      );
      await tester.tap(find.text('View Final Result & Full Itinerary'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Final Result Dossier'), findsOneWidget);
      expect(find.text('3 · Executive Concierge Final Result'), findsOneWidget);
      expect(
        find.text('1 · Complete Day-by-Day Route & Neighborhoods'),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const Key('close_final_result_sheet_button')),
      );
      await tester.pumpAndSettle();

      // Switch to Tab 4: ADK Studio -> verify Live Logger has recorded telemetry
      await tester.tap(find.text('ADK Studio'));
      await tester.pumpAndSettle();

      expect(find.byType(PocketSquadAdkStudioTab), findsOneWidget);
      expect(find.text('Pocket Squad ADK Studio'), findsOneWidget);
      expect(find.byType(AdkAgentLoggerView), findsOneWidget);
      expect(viewModel.agentLogs.length, greaterThanOrEqualTo(4));
      expect(find.text('No agent logs recorded yet.'), findsNothing);

      // Open Engine Mode Sheet from AppBar settings button
      await tester.tap(find.byKey(const Key('engine_mode_settings_button')));
      await tester.pumpAndSettle();

      expect(find.text(LlmEngineMode.onDeviceLiteRt.label), findsWidgets);
      expect(find.text(LlmEngineMode.lanOllama.label), findsWidgets);
    },
  );

  testWidgets(
    'ModelDownloadScreen enables Download CTA on Wi-Fi and allows skipping to Workspace',
    (WidgetTester tester) async {
      final wifiService = _FakeWifiService(wifiConnected: true);
      final downloadService = _FakeModelDownloadService(existingPath: null);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(sharedPreferences),
            appStorageServiceProvider.overrideWithValue(storageService),
            networkConnectivityServiceProvider.overrideWithValue(wifiService),
            modelDownloadServiceProvider.overrideWithValue(downloadService),
            liteRtChatDriverProvider.overrideWithValue(fakeDriver),
          ],
          child: const PocketSquadApp(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ModelDownloadScreen), findsOneWidget);
      expect(find.text('Wi-Fi Connected'), findsOneWidget);
      expect(find.text('Download On-Device Model (2.58 GB)'), findsOneWidget);

      // Tap Switch Engine / LAN to open EngineModeSheet and switch to LAN Ollama
      await tester.ensureVisible(
        find.byKey(const Key('switch_engine_mode_button')),
      );
      await tester.tap(find.byKey(const Key('switch_engine_mode_button')));
      await tester.pumpAndSettle();

      await tester.tap(find.text(LlmEngineMode.lanOllama.label));
      await tester.pumpAndSettle();

      await tester.ensureVisible(
        find.byKey(const Key('apply_engine_mode_button')),
      );
      await tester.tap(find.byKey(const Key('apply_engine_mode_button')));
      await tester.pumpAndSettle();

      expect(find.byType(PocketSquadWorkspaceScreen), findsOneWidget);
    },
  );

  testWidgets(
    'FormattedAgentMessageView splits concatenated multi-agent output, renders Markdown tables without raw pipes, and highlights Day headers',
    (WidgetTester tester) async {
      const rawConcatenated = '''
### 🧭 ScoutAgent — Destination & Route
### Día 1: Centro Histórico & Monserrate
* **Mañana**: Ascenso al Cerro de Monserrate y visita a La Candelaria.
| Categoría | Estimado USD | Notas |
| :--- | :--- | :--- |
| Alojamiento | \$110 | Boutique Hotel |

### 💰 BudgetAuditorAgent — Financial Audit
* **Grand Total**: \$990.00 USD (WITHIN BUDGET)

### ✨ ConciergeAgent — Final Brief & Vault
### Day 2: Zona G & Chapinero
* **Insider Tip**: Reserva con anticipación en Leo.
''';

      final sections = FormattedAgentMessageView.splitAgentSections(
        rawConcatenated,
        fallbackAuthor: 'scout_agent',
      );

      expect(sections.length, 3);
      expect(sections[0].author, 'scout_agent');
      expect(sections[0].content, contains('Día 1: Centro Histórico'));
      expect(sections[0].content, isNot(contains('ScoutAgent')));
      expect(sections[1].author, 'budget_auditor_agent');
      expect(sections[1].content, contains('Grand Total'));
      expect(sections[2].author, 'concierge_agent');
      expect(sections[2].content, contains('Day 2: Zona G'));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: FormattedAgentMessageView(text: sections[0].content),
            ),
          ),
        ),
      );

      // Day header pill with place icon is rendered
      expect(find.byIcon(Icons.place_rounded), findsWidgets);
      expect(
        find.textContaining('Día 1: Centro Histórico & Monserrate'),
        findsOneWidget,
      );
      // Markdown table cells are rendered without raw separator row
      expect(find.text('Categoría'), findsOneWidget);
      expect(find.text('Alojamiento'), findsOneWidget);
      expect(find.text('\$110'), findsOneWidget);
      expect(find.textContaining(':---'), findsNothing);
    },
  );
}

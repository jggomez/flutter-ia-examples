import 'dart:io';

import 'package:adk_dart/adk_core.dart';
import 'package:adk_pocket_squad/data/agents/pocket_squad_agent_factory.dart';
import 'package:adk_pocket_squad/data/llm/litert_chat_driver.dart';
import 'package:adk_pocket_squad/data/repositories/pocket_squad_repository.dart';
import 'package:adk_pocket_squad/data/services/app_storage_service.dart';
import 'package:adk_pocket_squad/data/services/model_download_service.dart';
import 'package:adk_pocket_squad/data/services/network_connectivity_service.dart';
import 'package:adk_pocket_squad/domain/models/budget_breakdown.dart';
import 'package:adk_pocket_squad/domain/models/llm_engine_config.dart';
import 'package:adk_pocket_squad/domain/models/saved_trip.dart';
import 'package:adk_pocket_squad/domain/use_cases/calculate_trip_budget_use_case.dart';
import 'package:adk_pocket_squad/domain/use_cases/evaluate_trip_intake_use_case.dart';
import 'package:adk_pocket_squad/domain/use_cases/save_trip_plan_use_case.dart';
import 'package:flutter_adk/src/controllers/adk_chat_controller.dart';
import 'package:flutter_adk/src/models/adk_chat_message.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _StubWifiService implements NetworkConnectivityService {
  _StubWifiService({this.wifi = true});
  bool wifi;

  @override
  Future<bool> isWifiConnected() async => wifi;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;
  late AppStorageService storageService;
  late FakeLiteRtChatDriver fakeDriver;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    prefs = await SharedPreferences.getInstance();
    storageService = AppStorageService(sharedPreferences: prefs);
    fakeDriver = FakeLiteRtChatDriver();
    await fakeDriver.initialize(modelFilePath: '/mock/gemma-4-E2B-it.litertlm');
  });

  tearDown(() async {
    await fakeDriver.dispose();
  });

  group('PocketSquadTools & SequentialAgent 3-Agent Pipeline', () {
    test('executes scout_agent -> budget_auditor_agent -> concierge_agent via AdkChatController, populates session.state, and persists SavedTrip', () async {
      final stepTransitions = <String>[];
      BudgetBreakdown? calculatedBudget;
      SavedTrip? savedTrip;

      final bundle = PocketSquadAgentFactory.create(
        config: const LlmEngineConfig(mode: LlmEngineMode.onDeviceLiteRt),
        driver: fakeDriver,
        storageService: storageService,
        onAgentStepUpdate: (agentName, status) {
          stepTransitions.add('$agentName:$status');
        },
        onBudgetCalculated: (breakdown) {
          calculatedBudget = breakdown;
        },
        onTripSaved: (trip) {
          savedTrip = trip;
        },
      );

      expect(bundle.pipelineAgent.name, equals('pocket_squad_pipeline'));
      expect(bundle.pipelineAgent.subAgents, hasLength(3));
      expect(bundle.scoutAgent.tools, isEmpty);
      expect(bundle.budgetAuditorAgent.tools, hasLength(1));
      expect(bundle.conciergeAgent.tools, hasLength(1));

      final controller = AdkChatController(
        agent: bundle.pipelineAgent,
        appName: 'pocket_squad_test',
        userId: 'traveler_1',
        sessionId: 'session_kyoto',
        sessionService: bundle.sessionService,
      );
      addTearDown(controller.dispose);

      await controller.sendMessage(
        'Plan a 4-day Kyoto Cultural Odyssey in Kyoto, Japan with a total budget of \$1,200 USD (convert to JPY).',
      );

      expect(controller.currentError, isNull);
      expect(calculatedBudget, isNotNull);
      expect(calculatedBudget!.days, equals(4));
      expect(calculatedBudget!.targetCurrency, equals('JPY'));

      expect(savedTrip, isNotNull);
      expect(savedTrip!.destination, contains('Kyoto'));

      // Verify all 3 agent callbacks fired
      expect(
        stepTransitions,
        containsAll(<String>[
          'scout_agent:running',
          'scout_agent:completed',
          'budget_auditor_agent:running',
          'budget_auditor_agent:completed',
          'concierge_agent:running',
          'concierge_agent:completed',
        ]),
      );

      // Verify session.state contains all 3 outputKey artifacts
      final session = await controller.sessionService.getSession(
        appName: controller.appName,
        userId: controller.userId,
        sessionId: controller.sessionId,
      );
      expect(session, isNotNull);
      expect(session!.state['itinerary_draft'], isNotNull);
      expect(session.state['budget_audit'], isNotNull);
      expect(session.state['final_concierge_brief'], isNotNull);

      // Verify SavedTrip is persisted in AppStorageService
      final persistedTrips = await storageService.loadSavedTrips();
      expect(persistedTrips, hasLength(1));
      expect(persistedTrips.first.destination, contains('Kyoto'));

      // Verify tool call messages were emitted to AdkChatController
      final toolMessages = controller.messages
          .where((m) => m.role == AdkMessageRole.tool)
          .toList();
      expect(toolMessages.length, greaterThanOrEqualTo(4));
    });

    test('supports LAN Ollama mode via LiteLlm in PocketSquadAgentFactory', () {
      final bundle = PocketSquadAgentFactory.create(
        config: const LlmEngineConfig(
          mode: LlmEngineMode.lanOllama,
          ollamaBaseUrl: 'http://192.168.1.25:11434/v1',
          ollamaModel: 'ollama_chat/gemma3:4b',
        ),
        driver: fakeDriver,
        storageService: storageService,
      );

      expect(bundle.llm, isA<LiteLlm>());
      final liteLlm = bundle.llm as LiteLlm;
      expect(liteLlm.model, equals('ollama_chat/gemma3:4b'));
      expect(liteLlm.baseUrl, equals('http://192.168.1.25:11434/v1'));
    });
  });

  group('PocketSquadRepository', () {
    test('coordinates readiness, storage, and bundle creation', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'pocket_repo_test_',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final modelFile = File(
        '${tempDir.path}/${ModelDownloadService.modelFileName}',
      );
      await modelFile.writeAsBytes(List<int>.filled(64, 7));

      final downloadService = ModelDownloadService(
        documentsDirectoryProvider: () async => tempDir,
        supportDirectoryProvider: () async => tempDir,
        minValidBytesOverride: 16,
      );

      final repository = PocketSquadRepository(
        downloadService: downloadService,
        connectivityService: _StubWifiService(wifi: true),
        storageService: storageService,
        chatDriver: fakeDriver,
      );

      final readiness = await repository.checkModelReadiness();
      expect(readiness.isReady, isTrue);
      expect(fakeDriver.isInitialized, isTrue);

      final bundle = repository.createSquadBundle(
        config: const LlmEngineConfig(),
      );
      expect(bundle.pipelineAgent.subAgents, hasLength(3));
      expect(bundle.rootAgent, same(bundle.coordinatorAgent));
    });
  });

  group('CoordinatorAgent Conversational Intake & AutoFlow Delegation', () {
    test('greeting ("Hola") on rootAgent responds conversationally in Spanish without running the 3-agent pipeline or saving a trip', () async {
      final stepTransitions = <String>[];
      BudgetBreakdown? calculatedBudget;
      SavedTrip? savedTrip;

      final bundle = PocketSquadAgentFactory.create(
        config: const LlmEngineConfig(mode: LlmEngineMode.onDeviceLiteRt),
        driver: fakeDriver,
        storageService: storageService,
        onAgentStepUpdate: (agentName, status) {
          stepTransitions.add('$agentName:$status');
        },
        onBudgetCalculated: (breakdown) {
          calculatedBudget = breakdown;
        },
        onTripSaved: (trip) {
          savedTrip = trip;
        },
      );

      expect(bundle.rootAgent.name, equals('coordinator_agent'));
      expect(bundle.coordinatorAgent.subAgents, contains(bundle.pipelineAgent));

      final controller = AdkChatController(
        agent: bundle.rootAgent,
        appName: 'pocket_squad_test',
        userId: 'traveler_hola',
        sessionId: 'session_hola',
        sessionService: bundle.sessionService,
      );
      addTearDown(controller.dispose);

      await controller.sendMessage('Hola');

      expect(controller.currentError, isNull);
      expect(calculatedBudget, isNull);
      expect(savedTrip, isNull);

      expect(
        stepTransitions,
        containsAll(<String>[
          'coordinator_agent:running',
          'coordinator_agent:completed',
        ]),
      );
      expect(stepTransitions, isNot(contains('scout_agent:running')));
      expect(stepTransitions, isNot(contains('budget_auditor_agent:running')));
      expect(stepTransitions, isNot(contains('concierge_agent:running')));

      final assistantMessages = controller.messages
          .where((m) => m.role == AdkMessageRole.model)
          .toList();
      expect(assistantMessages, isNotEmpty);
      expect(
        assistantMessages.last.text,
        contains('### 🎯 CoordinatorAgent — Travel Intake'),
      );

      final session = await controller.sessionService.getSession(
        appName: controller.appName,
        userId: controller.userId,
        sessionId: controller.sessionId,
      );
      expect(session, isNotNull);
      expect(session!.state['itinerary_draft'], isNull);
      expect(session.state['budget_audit'], isNull);
      expect(session.state['final_concierge_brief'], isNull);

      final persistedTrips = await storageService.loadSavedTrips();
      expect(persistedTrips, isEmpty);
    });

    test('multi-turn intake ("Hola" -> "Quiero ir a Kioto" -> "Por 4 días con un presupuesto de \$1200 USD") delegates via transfer_to_agent on turn 3 and completes the 3-agent pipeline', () async {
      final stepTransitions = <String>[];
      BudgetBreakdown? calculatedBudget;
      SavedTrip? savedTrip;

      final bundle = PocketSquadAgentFactory.create(
        config: const LlmEngineConfig(mode: LlmEngineMode.onDeviceLiteRt),
        driver: fakeDriver,
        storageService: storageService,
        onAgentStepUpdate: (agentName, status) {
          stepTransitions.add('$agentName:$status');
        },
        onBudgetCalculated: (breakdown) {
          calculatedBudget = breakdown;
        },
        onTripSaved: (trip) {
          savedTrip = trip;
        },
      );

      final controller = AdkChatController(
        agent: bundle.rootAgent,
        appName: 'pocket_squad_test',
        userId: 'traveler_multiturn',
        sessionId: 'session_multiturn',
        sessionService: bundle.sessionService,
      );
      addTearDown(controller.dispose);

      // Turn 1: Greeting only
      await controller.sendMessage('Hola');
      expect(calculatedBudget, isNull);
      expect(savedTrip, isNull);
      expect(await storageService.loadSavedTrips(), isEmpty);

      // Turn 2: Destination only (still missing days and budget)
      await controller.sendMessage('Quiero ir a Kioto');
      expect(calculatedBudget, isNull);
      expect(savedTrip, isNull);
      expect(await storageService.loadSavedTrips(), isEmpty);

      // Turn 3: Days and budget provided -> triggers transfer_to_agent('pocket_squad_pipeline')
      await controller.sendMessage(
        'Por 4 días con un presupuesto de \$1200 USD',
      );

      expect(controller.currentError, isNull);
      expect(calculatedBudget, isNotNull);
      expect(calculatedBudget!.days, equals(4));
      expect(calculatedBudget!.userBudgetUsd, equals(1200.0));
      expect(calculatedBudget!.targetCurrency, equals('JPY'));

      expect(savedTrip, isNotNull);
      expect(savedTrip!.destination, contains('Kyoto'));

      expect(
        stepTransitions,
        containsAll(<String>[
          'coordinator_agent:running',
          'scout_agent:running',
          'scout_agent:completed',
          'budget_auditor_agent:running',
          'budget_auditor_agent:completed',
          'concierge_agent:running',
          'concierge_agent:completed',
        ]),
      );

      final session = await controller.sessionService.getSession(
        appName: controller.appName,
        userId: controller.userId,
        sessionId: controller.sessionId,
      );
      expect(session, isNotNull);
      expect(session!.state['itinerary_draft'], isNotNull);
      final itineraryDraft = session.state['itinerary_draft'] as String;
      expect(itineraryDraft, contains('### Día 1'));
      expect(itineraryDraft, contains('### Día 2'));
      expect(itineraryDraft, contains('### Día 3'));
      expect(itineraryDraft, contains('### Día 4'));
      expect(itineraryDraft, contains('Mañana'));
      expect(itineraryDraft, contains('Tarde'));
      expect(itineraryDraft, contains('Noche'));
      expect(itineraryDraft, contains('Fushimi Inari'));

      expect(session.state['budget_audit'], isNotNull);
      expect(session.state['final_concierge_brief'], isNotNull);
      final conciergeBrief = session.state['final_concierge_brief'] as String;
      expect(conciergeBrief, contains('Gastronomía'));
      expect(conciergeBrief, contains('Equipaje'));

      final persistedTrips = await storageService.loadSavedTrips();
      expect(persistedTrips, hasLength(1));
      expect(persistedTrips.first.destination, contains('Kyoto'));

      // Turn 4: Starting a new trip conversation after pipeline completion resets intake
      stepTransitions.clear();
      await controller.sendMessage('Hola de nuevo');
      expect(
        stepTransitions,
        containsAll(<String>[
          'coordinator_agent:running',
          'coordinator_agent:completed',
        ]),
      );
      expect(stepTransitions, isNot(contains('scout_agent:running')));
      expect(await storageService.loadSavedTrips(), hasLength(1));
    });

    test('one-shot complete mission prompt on rootAgent immediately delegates to pocket_squad_pipeline in a single turn', () async {
      BudgetBreakdown? calculatedBudget;
      SavedTrip? savedTrip;

      final bundle = PocketSquadAgentFactory.create(
        config: const LlmEngineConfig(mode: LlmEngineMode.onDeviceLiteRt),
        driver: fakeDriver,
        storageService: storageService,
        onBudgetCalculated: (breakdown) {
          calculatedBudget = breakdown;
        },
        onTripSaved: (trip) {
          savedTrip = trip;
        },
      );

      final controller = AdkChatController(
        agent: bundle.rootAgent,
        appName: 'pocket_squad_test',
        userId: 'traveler_oneshot',
        sessionId: 'session_oneshot',
        sessionService: bundle.sessionService,
      );
      addTearDown(controller.dispose);

      await controller.sendMessage(
        'Plan a 4-day Kyoto Cultural Odyssey in Kyoto, Japan with a total budget of \$1,200 USD (convert to JPY).',
      );

      expect(controller.currentError, isNull);
      expect(calculatedBudget, isNotNull);
      expect(calculatedBudget!.days, equals(4));
      expect(savedTrip, isNotNull);
      expect(savedTrip!.destination, contains('Kyoto'));
    });
  });

  group('Domain Use Cases', () {
    test('EvaluateTripIntakeUseCase, CalculateTripBudgetUseCase, and SaveTripPlanUseCase execute deterministically', () async {
      const evaluateIntake = EvaluateTripIntakeUseCase();
      const calculateBudget = CalculateTripBudgetUseCase();
      final saveTrip = SaveTripPlanUseCase(storageService: storageService);

      final readiness = evaluateIntake(
        'Quiero ir a Cartagena por 3 días con \$750 USD',
      );
      expect(readiness.isComplete, isTrue);
      expect(readiness.isSpanish, isTrue);
      expect(readiness.detectedDestination, equals('Cartagena'));
      expect(readiness.detectedDays, equals(3));
      expect(readiness.detectedBudget, equals(750.0));

      final breakdown = calculateBudget(
        days: readiness.detectedDays!,
        lodgingPerNightUsd: 110.0,
        foodPerDayUsd: 45.0,
        activitiesTotalUsd: 120.0,
        targetCurrency: 'COP',
        userBudgetUsd: readiness.detectedBudget,
      );
      expect(breakdown.withinBudget, isTrue);
      expect(breakdown.targetCurrency, equals('COP'));

      final saved = await saveTrip(
        destination: 'Cartagena, Colombia',
        days: 3,
        itinerarySummary: '### Día 1: Centro Histórico y Ciudad Amurallada',
        packingChecklist: const <String>['Bloqueador solar', 'Ropa de lino'],
        budgetBreakdown: breakdown,
        conciergeNotes: 'Madruga a las 8:00 AM.',
        engineLabel: 'On-Device Gemma 4 E2B (LiteRT-LM)',
      );
      expect(saved.destination, equals('Cartagena, Colombia'));
      final loaded = await storageService.loadSavedTrips();
      expect(loaded, hasLength(1));
      expect(loaded.first.id, equals(saved.id));
    });
  });
}

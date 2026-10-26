import 'package:adk_dart/adk_core.dart';
import 'package:adk_pocket_squad/data/llm/litert_chat_driver.dart';
import 'package:adk_pocket_squad/data/llm/on_device_litert_gemma_llm.dart';
import 'package:flutter_test/flutter_test.dart';

class _ScriptedChatDriver implements LiteRtChatDriver {
  _ScriptedChatDriver(this.responses);

  final List<String> responses;
  int _index = 0;
  bool _initialized = true;
  String? _modelPath = '/mock/gemma-4-E2B-it.litertlm';
  final List<String> recordedPrompts = <String>[];
  final List<int> recordedMaxOutputTokens = <int>[];

  @override
  bool get isInitialized => _initialized;

  @override
  String? get activeModelPath => _modelPath;

  @override
  Future<void> initialize({required String modelFilePath}) async {
    _initialized = true;
    _modelPath = modelFilePath;
  }

  @override
  Future<String> generateCompletion({
    required String prompt,
    String? systemInstruction,
    int maxOutputTokens = 320,
  }) async {
    recordedPrompts.add(prompt);
    recordedMaxOutputTokens.add(maxOutputTokens);
    if (_index < responses.length) {
      return responses[_index++];
    }
    return responses.isEmpty ? 'Completed turn.' : responses.last;
  }

  @override
  Future<void> dispose() async {
    _initialized = false;
  }
}

void main() {
  group('LiteRtChatDriverImpl.hasRepetitionLoop', () {
    test('detects tandem phrase repetition and allows clean prose', () {
      expect(
        LiteRtChatDriverImpl.hasRepetitionLoop(
          'Visit Fushimi Inari early morning and enjoy matcha in Uji.',
        ),
        isFalse,
      );
      expect(
        LiteRtChatDriverImpl.hasRepetitionLoop(
          'Book ahead now. Book ahead now. Book ahead now. Book ahead now.',
        ),
        isTrue,
      );
    });
  });

  group('FakeLiteRtChatDriver', () {
    test(
      'initializes, generates role-specific completions, and disposes',
      () async {
        final driver = FakeLiteRtChatDriver();
        expect(driver.isInitialized, isFalse);

        await driver.initialize(modelFilePath: '/tmp/gemma-4-E2B-it.litertlm');
        expect(driver.isInitialized, isTrue);
        expect(driver.activeModelPath, equals('/tmp/gemma-4-E2B-it.litertlm'));

        final scoutReply = await driver.generateCompletion(
          prompt: r'Plan a 4-day Kyoto trip with $1,200 USD budget in JPY.',
          systemInstruction: 'You are scout_agent.',
        );
        expect(scoutReply, contains('Kyoto'));

        await driver.dispose();
        expect(driver.isInitialized, isFalse);
      },
    );
  });

  group('OnDeviceLiteRtGemmaLlm', () {
    test('extractBudgetArgsFromRequest extracts destination, days, costs, currency, and budget', () {
      final request = LlmRequest(
        contents: <Content>[
          Content.userText(
            'Plan a 4-day Kyoto Cultural Odyssey in Kyoto, Japan with a total budget of \$1,200 USD (convert to JPY). '
            'Lodging: \$140/night, Food: \$55/day, Activities: \$180 total.',
          ),
        ],
      );

      final args = OnDeviceLiteRtGemmaLlm.extractBudgetArgsFromRequest(request);
      expect(args['days'], equals(4));
      expect(args['target_currency'], equals('JPY'));
      expect(args['user_budget_usd'], equals(1200.0));
      expect(args['lodging_per_night_usd'], equals(140.0));
      expect(args['food_per_day_usd'], equals(55.0));
      expect(args['activities_total_usd'], equals(180.0));
    });

    test('Case 1 (Tool Call Required): emits FunctionCall when tool is attached and no functionResponse exists yet', () async {
      final driver = _ScriptedChatDriver(<String>[
        'Let me calculate that using prose without strict JSON tags.',
      ]);
      final turnEvents = <String>[];
      final llm = OnDeviceLiteRtGemmaLlm(
        driver: driver,
        onTurnEvent: (agent, stage) => turnEvents.add('$agent:$stage'),
      );

      final dummyTool = FunctionTool(
        name: 'calculate_budget_math',
        description: 'Computes exact trip budget.',
        func: (Map<String, dynamic> args) => args,
      );

      final request = LlmRequest(
        config: GenerateContentConfig(
          systemInstruction: 'You are budget_auditor_agent.',
          tools: <ToolDeclaration>[
            ToolDeclaration(
              functionDeclarations: <FunctionDeclaration>[
                FunctionDeclaration(name: 'calculate_budget_math'),
              ],
            ),
          ],
        ),
        toolsDict: <String, BaseTool>{'calculate_budget_math': dummyTool},
        contents: <Content>[
          Content.userText(
            'Plan a 3-day Cartagena Caribbean Escape in Cartagena, Colombia with a total budget of \$750 USD (convert to COP).',
          ),
        ],
      );

      final responses = await llm.generateContent(request).toList();
      expect(responses, hasLength(1));
      final functionCalls = responses.first.getFunctionCalls();
      expect(functionCalls, hasLength(1));
      expect(functionCalls.first.name, equals('calculate_budget_math'));
      expect(functionCalls.first.args['days'], equals(3));
      expect(functionCalls.first.args['target_currency'], equals('COP'));
      expect(functionCalls.first.args['user_budget_usd'], equals(750.0));
      expect(turnEvents, isNotEmpty);
    });

    test('Case 2 (Agent Narrative Response): emits prefixed markdown when functionResponse is already present', () async {
      final driver = _ScriptedChatDriver(<String>[
        'The 4-day Kyoto trip is within the \$1,200 USD budget.',
      ]);
      final llm = OnDeviceLiteRtGemmaLlm(driver: driver);

      final dummyTool = FunctionTool(
        name: 'calculate_budget_math',
        description: 'Computes exact trip budget.',
        func: (Map<String, dynamic> args) => args,
      );

      final request = LlmRequest(
        config: GenerateContentConfig(
          systemInstruction: 'You are budget_auditor_agent.',
        ),
        toolsDict: <String, BaseTool>{'calculate_budget_math': dummyTool},
        contents: <Content>[
          Content.userText('Plan a 4-day Kyoto trip with \$1,200 USD.'),
          Content(
            role: 'model',
            parts: <Part>[
              Part.fromFunctionCall(
                name: 'calculate_budget_math',
                args: <String, dynamic>{'days': 4},
              ),
            ],
          ),
          Content(
            role: 'user',
            parts: <Part>[
              Part.fromFunctionResponse(
                name: 'calculate_budget_math',
                response: <String, dynamic>{
                  'grandTotalUsd': 1100.0,
                  'withinBudget': true,
                },
              ),
            ],
          ),
        ],
      );

      final responses = await llm.generateContent(request).toList();
      expect(responses, hasLength(1));
      expect(responses.first.getFunctionCalls(), isEmpty);
      final text = responses.first.content!.parts
          .map((p) => p.text ?? '')
          .join();
      expect(text, contains('### 💰 BudgetAuditorAgent — Financial Audit'));
      expect(text, contains('within the \$1,200 USD budget'));
    });

    test('evaluateIntakeText detects greeting ("hola") as incomplete Spanish intake with 3 missing fields', () {
      final readiness = OnDeviceLiteRtGemmaLlm.evaluateIntakeText('hola');
      expect(readiness.isComplete, isFalse);
      expect(readiness.isSpanish, isTrue);
      expect(readiness.hasDestination, isFalse);
      expect(readiness.hasDays, isFalse);
      expect(readiness.hasBudget, isFalse);
      expect(
        readiness.missingFields,
        equals(<String>['destination', 'days', 'budget']),
      );
    });

    test('evaluateIntakeText detects partial intake ("Quiero ir a Tokio por 4 días") with missing budget', () {
      final readiness = OnDeviceLiteRtGemmaLlm.evaluateIntakeText(
        'Quiero ir a Tokio por 4 días',
      );
      expect(readiness.isSpanish, isTrue);
      expect(readiness.hasDestination, isTrue);
      expect(readiness.hasDays, isTrue);
      expect(readiness.detectedDays, equals(4));
      expect(readiness.hasBudget, isFalse);
      expect(readiness.isComplete, isFalse);
      expect(readiness.missingFields, equals(<String>['budget']));
    });

    test('evaluateIntakeText detects complete multi-turn intake ("Hola | Quiero ir a Tokio | 4 días y tengo \$1500 USD")', () {
      final readiness = OnDeviceLiteRtGemmaLlm.evaluateIntakeText(
        'Hola | Quiero ir a Tokio | 4 días y tengo \$1500 USD',
      );
      expect(readiness.isComplete, isTrue);
      expect(readiness.missingFields, isEmpty);
      expect(readiness.detectedDestination, isNotNull);
      expect(
        readiness.detectedDestination!.toLowerCase(),
        anyOf(contains('tokio'), contains('tokyo')),
      );
      expect(readiness.detectedDays, equals(4));
      expect(readiness.detectedBudget, equals(1500.0));
    });

    test('coordinator_agent replies conversationally when incomplete and calls transfer_to_agent when complete', () async {
      final fakeDriver = FakeLiteRtChatDriver(
        initiallyInitialized: true,
        initialModelPath: '/mock/gemma-4-E2B-it.litertlm',
      );
      final llm = OnDeviceLiteRtGemmaLlm(driver: fakeDriver);
      final transferTool = FunctionTool(
        name: OnDeviceLiteRtGemmaLlm.transferToAgentToolName,
        description: 'Transfer to sub-agent.',
        func: (Map<String, dynamic> args) => args,
      );

      final greetingRequest = LlmRequest(
        config: GenerateContentConfig(
          systemInstruction: 'You are coordinator_agent.',
        ),
        toolsDict: <String, BaseTool>{
          OnDeviceLiteRtGemmaLlm.transferToAgentToolName: transferTool,
        },
        contents: <Content>[Content.userText('Hola')],
      );

      final greetingResponses = await llm
          .generateContent(greetingRequest)
          .toList();
      expect(greetingResponses, hasLength(1));
      expect(greetingResponses.first.getFunctionCalls(), isEmpty);
      final greetingText = greetingResponses.first.content!.parts
          .map((p) => p.text ?? '')
          .join();
      expect(greetingText, contains('### 🎯 CoordinatorAgent — Travel Intake'));

      final readyRequest = LlmRequest(
        config: GenerateContentConfig(
          systemInstruction: 'You are coordinator_agent.',
        ),
        toolsDict: <String, BaseTool>{
          OnDeviceLiteRtGemmaLlm.transferToAgentToolName: transferTool,
        },
        contents: <Content>[
          Content.userText('Hola'),
          Content.modelText(greetingText),
          Content.userText(
            'Quiero ir a Kioto por 4 días con un presupuesto de \$1200 USD',
          ),
        ],
      );

      final readyResponses = await llm.generateContent(readyRequest).toList();
      expect(readyResponses, hasLength(1));
      final calls = readyResponses.first.getFunctionCalls();
      expect(calls, hasLength(1));
      expect(
        calls.first.name,
        equals(OnDeviceLiteRtGemmaLlm.transferToAgentToolName),
      );
      expect(
        calls.first.args['agent_name'],
        equals(OnDeviceLiteRtGemmaLlm.pipelineAgentTargetName),
      );
    });

    test('scout_agent uses maxOutputTokens: 550, omits USD cost input requests from prompt, and enforces Day-by-Day itinerary with real places when model outputs only budget tables', () async {
      final driver = _ScriptedChatDriver(<String>[
        '### 💰 Budget Audit & Assumptions\n| Category | Cost |\n| Lodging | \$330 |',
      ]);
      final llm = OnDeviceLiteRtGemmaLlm(driver: driver);

      final request = LlmRequest(
        config: GenerateContentConfig(
          systemInstruction: 'You are scout_agent.',
        ),
        contents: <Content>[
          Content.userText(
            'Quiero ir a Cartagena por 3 días con un presupuesto de \$750 USD',
          ),
        ],
      );

      final responses = await llm.generateContent(request).toList();
      expect(responses, hasLength(1));
      expect(driver.recordedMaxOutputTokens.last, equals(550));
      expect(
        driver.recordedPrompts.last,
        isNot(contains('lodging_per_night_usd')),
      );

      final text = responses.first.content!.parts
          .map((p) => p.text ?? '')
          .join();
      expect(text, contains('### 🧭 ScoutAgent — Destination & Route'));
      expect(text, contains('### Día 1'));
      expect(text, contains('### Día 2'));
      expect(text, contains('### Día 3'));
      expect(text, contains('Mañana'));
      expect(text, contains('Tarde'));
      expect(text, contains('Noche'));
      expect(text, contains('Ciudad Amurallada'));
      expect(text, contains('Getsemaní'));
    });

    test('concierge_agent prompt omits budgetBreakdown JSON and requests local gastronomy, insider logistics, and packing checklist', () async {
      final driver = _ScriptedChatDriver(<String>[
        '- **Gastronomía y Platos Típicos**: Posta negra cartagenera, ceviche de camarón y arepa de huevo.\n'
            '- **Consejos Locales y Logística**: Madruga a las 7:00 AM para caminar por el Centro Histórico.\n'
            '- **Lista de Equipaje**: Ropa de lino, bloqueador solar, sombrero y zapatos cómodos.',
      ]);
      final llm = OnDeviceLiteRtGemmaLlm(driver: driver);

      final request = LlmRequest(
        config: GenerateContentConfig(
          systemInstruction: 'You are concierge_agent.',
        ),
        contents: <Content>[
          Content.userText(
            'Quiero ir a Cartagena por 3 días con un presupuesto de \$750 USD',
          ),
          Content(
            role: 'model',
            parts: <Part>[
              Part.fromFunctionCall(
                name: 'save_trip_plan',
                args: <String, dynamic>{'destination': 'Cartagena, Colombia'},
              ),
            ],
          ),
          Content(
            role: 'user',
            parts: <Part>[
              Part.fromFunctionResponse(
                name: 'save_trip_plan',
                response: <String, dynamic>{
                  'status': 'saved',
                  'budgetBreakdown': <String, dynamic>{
                    'grandTotalUsd': 680.0,
                    'lodgingPerNightUsd': 110.0,
                  },
                },
              ),
            ],
          ),
        ],
      );

      final responses = await llm.generateContent(request).toList();
      expect(responses, hasLength(1));
      expect(driver.recordedMaxOutputTokens.last, equals(340));
      expect(driver.recordedPrompts.last, isNot(contains('grandTotalUsd')));
      expect(
        driver.recordedPrompts.last,
        isNot(contains('lodgingPerNightUsd')),
      );

      final text = responses.first.content!.parts
          .map((p) => p.text ?? '')
          .join();
      expect(text, contains('### ✨ ConciergeAgent — Final Brief & Vault'));
      expect(text, contains('Gastronomía'));
    });
  });
}

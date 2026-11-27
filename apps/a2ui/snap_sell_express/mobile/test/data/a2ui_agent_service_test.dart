import 'dart:async';
import 'dart:convert';

import 'package:a2ui_core/a2ui_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobile/core/config/app_config.dart';
import 'package:mobile/data/services/a2a_client.dart';
import 'package:mobile/data/services/a2ui_agent_service.dart';
import 'package:mobile/domain/models/surface_event.dart';
import 'package:mobile/ui/catalog/snap_sell_catalog.dart';

import '../support/fakes.dart';

String _sse(List<Map<String, Object?>> results) => results
    .map(
      (Map<String, Object?> r) =>
          'data: ${jsonEncode(<String, Object?>{'jsonrpc': '2.0', 'id': '1', 'result': r})}\n\n',
    )
    .join();

Map<String, Object?> _status(
  String state, {
  List<Map<String, Object?>> parts = const <Map<String, Object?>>[],
  bool isFinal = false,
}) => <String, Object?>{
  'kind': 'status-update',
  'contextId': 'ctx-1',
  'taskId': 'task-1',
  'final': isFinal,
  'status': <String, Object?>{
    'state': state,
    'message': <String, Object?>{
      'kind': 'message',
      'role': 'agent',
      'messageId': 'a',
      'parts': parts,
    },
  },
};

Map<String, Object?> _a2uiPart(Map<String, Object?> message) =>
    <String, Object?>{
      'kind': 'data',
      'data': message,
      'metadata': <String, Object?>{'mimeType': a2uiMimeType},
    };

class _Server {
  final List<http.Request> requests = <http.Request>[];
  final List<String> Function(Map<String, Object?> body)? respond;
  _Server([this.respond]);

  late final MockClient client = MockClient((http.Request request) async {
    requests.add(request);
    final Map<String, Object?> body =
        jsonDecode(request.body) as Map<String, Object?>;
    return http.Response(
      (respond?.call(body) ?? <String>[]).join(),
      200,
      headers: <String, String>{'content-type': 'text/event-stream'},
    );
  });

  Map<String, Object?> message(int i) =>
      ((jsonDecode(requests[i].body) as Map<String, Object?>)['params']!
              as Map<String, Object?>)['message']!
          as Map<String, Object?>;
}

A2uiAgentService _service(_Server server) => A2uiAgentService(
  config: const AppConfig(baseUrl: 'http://agent.test', token: 'secret'),
  catalog: buildSnapSellCatalog(),
  client: A2aClient(
    endpoint: Uri.parse('http://agent.test'),
    httpClient: server.client,
    headers: const <String, String>{'Authorization': 'Bearer secret'},
  ),
);

void main() {
  test('A2aEvent flattens status, artifact and message results', () {
    final A2aEvent artifact = A2aEvent.fromResult(<String, Object?>{
      'kind': 'artifact-update',
      'taskId': 't',
      'artifact': <String, Object?>{
        'parts': <Object?>[
          <String, Object?>{'kind': 'text', 'text': 'hi'},
        ],
      },
    });
    expect(artifact.parts.single, isA<A2aTextPart>());
    final A2aEvent task = A2aEvent.fromResult(<String, Object?>{
      'kind': 'task',
      'id': 't1',
      'contextId': 'c1',
      'status': <String, Object?>{'state': 'submitted'},
    });
    expect(
      (task.taskId, task.contextId, task.state),
      ('t1', 'c1', 'submitted'),
    );
  });

  test(
    'a turn sends capabilities + photo and renders the createSurface',
    () async {
      final List<Map<String, Object?>> unsupported = loadContractExample(
        '05_unsupported_item.json',
      );
      final _Server server = _Server(
        (_) => <String>[
          _sse(<Map<String, Object?>>[
            _status(
              'working',
              parts: <Map<String, Object?>>[
                <String, Object?>{'kind': 'text', 'text': 'Not supported yet.'},
                _a2uiPart(unsupported.single),
              ],
            ),
            _status('completed', isFinal: true),
          ]),
        ],
      );
      final A2uiAgentService service = _service(server);
      addTearDown(service.dispose);
      final List<SurfaceEvent> events = <SurfaceEvent>[];
      final List<String> texts = <String>[];
      service.surfaceEvents.listen(events.add);
      service.textStream.listen(texts.add);

      await service.sendTurn(<A2aPart>[
        const A2aTextPart('Analyze this item'),
        A2aFilePart(
          bytes: kFakeTransparentPng,
          mimeType: 'image/png',
          name: 'x.png',
        ),
      ]);
      await Future<void>.delayed(Duration.zero);

      final http.Request request = server.requests.single;
      expect(request.headers['X-A2A-Extensions'], a2uiExtensionUri);
      expect(request.headers['Authorization'], 'Bearer secret');
      expect(request.headers['Accept'], 'text/event-stream');
      final Map<String, Object?> body =
          jsonDecode(request.body) as Map<String, Object?>;
      expect(body['method'], 'message/stream');
      final Map<String, Object?> message = server.message(0);
      expect(
        (message['parts']! as List<Object?>).map(
          (Object? p) => (p! as Map)['kind'],
        ),
        <String>['text', 'file'],
      );
      expect(
        (message['metadata']!
            as Map<String, Object?>)['a2uiRendererCapabilities'],
        <String, Object?>{
          '1.0': <String, Object?>{
            'supportedCatalogIds': <String>[AppConfig.snapSellCatalogId],
          },
        },
      );

      expect(events.single, isA<SurfaceCreated>());
      expect(service.surface('selling_unsupported'), isNotNull);
      expect(texts, <String>['Not supported yet.']);
    },
  );

  test('the next turn reuses the contextId the agent assigned', () async {
    final _Server server = _Server(
      (_) => <String>[
        _sse(<Map<String, Object?>>[_status('completed', isFinal: true)]),
      ],
    );
    final A2uiAgentService service = _service(server);
    addTearDown(service.dispose);
    await service.sendTurn(<A2aPart>[const A2aTextPart('one')]);
    await service.sendTurn(<A2aPart>[const A2aTextPart('two')]);
    expect(server.message(0).containsKey('contextId'), isFalse);
    expect(server.message(1)['contextId'], 'ctx-1');
  });

  test(
    're-creating an existing surface replaces it instead of failing',
    () async {
      final _Server server = _Server();
      final A2uiAgentService service = _service(server);
      addTearDown(service.dispose);
      final List<SurfaceEvent> events = <SurfaceEvent>[];
      final List<Object> errors = <Object>[];
      service.surfaceEvents.listen(events.add);
      service.errorStream.listen(errors.add);

      final Map<String, Object?> create = loadContractExample(
        '05_unsupported_item.json',
      ).single;
      service.applyA2uiMessage(create);
      service.applyA2uiMessage(create);
      await Future<void>.delayed(Duration.zero);

      expect(errors, isEmpty);
      expect(events.map((SurfaceEvent e) => e.runtimeType), <Type>[
        SurfaceCreated,
        SurfaceDeleted,
        SurfaceCreated,
      ]);
    },
  );

  test(
    'callAgentFunction goes to the agent and its answer is applied',
    () async {
      final Completer<void> answered = Completer<void>();
      final _Server server = _Server((Map<String, Object?> body) {
        final Map<String, Object?> message =
            (body['params']! as Map<String, Object?>)['message']!
                as Map<String, Object?>;
        final Map<String, Object?> data =
            ((message['parts']! as List<Object?>).single! as Map)['data']
                as Map<String, Object?>;
        final Map<String, Object?> call =
            data['callAgentFunction']! as Map<String, Object?>;
        scheduleMicrotask(answered.complete);
        return <String>[
          _sse(<Map<String, Object?>>[
            <String, Object?>{
              'kind': 'message',
              'role': 'agent',
              'messageId': 'r',
              'parts': <Object?>[
                _a2uiPart(<String, Object?>{
                  'version': '1.0',
                  'agentFunctionResponse': <String, Object?>{
                    'functionCallId': call['functionCallId'],
                    'value': 'competitive',
                  },
                }),
              ],
            },
          ]),
        ];
      });
      final A2uiAgentService service = _service(server);
      addTearDown(service.dispose);
      final List<Object> errors = <Object>[];
      service.errorStream.listen(errors.add);

      service.applyA2uiMessage(
        loadContractExample('04_listing_preview.json').single,
      );
      // The binder evaluates PriceRange.feedback only once the surface renders,
      // so trigger it explicitly through the processor.
      final Object? value = await service.processor.callAgentFunction(
        'selling_step_3_preview',
        FunctionCall(
          call: 'priceFeedback',
          catalogId: AppConfig.snapSellCatalogId,
          args: <String, Object?>{
            'askingPrice': 23400,
            'minPrice': 21500,
            'suggestedPrice': 23400,
            'maxPrice': 24900,
          },
        ),
      );
      await answered.future;

      expect(value, 'competitive');
      expect(server.message(0).containsKey('contextId'), isFalse);
      expect(errors, isEmpty);
    },
  );

  test('a failed task is reported on errorStream', () async {
    final _Server server = _Server(
      (_) => <String>[
        _sse(<Map<String, Object?>>[
          _status(
            'failed',
            isFinal: true,
            parts: <Map<String, Object?>>[
              <String, Object?>{
                'kind': 'text',
                'text': '403 PERMISSION_DENIED',
              },
            ],
          ),
        ]),
      ],
    );
    final A2uiAgentService service = _service(server);
    addTearDown(service.dispose);
    final List<Object> errors = <Object>[];
    service.errorStream.listen(errors.add);
    await service.sendTurn(<A2aPart>[const A2aTextPart('x')]);
    await Future<void>.delayed(Duration.zero);
    expect(errors.single.toString(), contains('PERMISSION_DENIED'));
  });
}

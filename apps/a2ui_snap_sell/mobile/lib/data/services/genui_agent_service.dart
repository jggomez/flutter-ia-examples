import 'dart:async';

import 'package:genui/genui.dart';
import 'package:genui_a2a/genui_a2a.dart';

import '../../core/config/app_config.dart';

/// Low-level service wrapping `genui_a2a`'s [A2uiAgentConnector] and
/// `genui`'s [A2uiTransportAdapter].
class GenUiAgentService {
  /// Creates a [GenUiAgentService] bound to [config] and [surfaceController].
  GenUiAgentService({
    required AppConfig config,
    required this.surfaceController,
    A2uiAgentConnector? connector,
  }) : _connector = connector ?? A2uiAgentConnector(url: config.uri) {
    _transportAdapter = A2uiTransportAdapter(onSend: _onSendToConnector);
    _incomingMessagesSub = _transportAdapter.incomingMessages.listen(
      surfaceController.handleMessage,
      onError: _errorController.add,
    );
    _connectorMessagesSub = _connector.stream.listen(
      surfaceController.handleMessage,
      onError: _errorController.add,
    );
    _connectorTextSub = _connector.textStream.listen(_textController.add);
    _transportTextSub = _transportAdapter.incomingText.listen(
      _textController.add,
    );
    _connectorErrorSub = _connector.errorStream.listen(_errorController.add);
  }

  /// The [SurfaceController] that receives parsed A2UI v0.9 messages.
  final SurfaceController surfaceController;

  final A2uiAgentConnector _connector;
  late final A2uiTransportAdapter _transportAdapter;
  late final StreamSubscription<Object?> _incomingMessagesSub;
  late final StreamSubscription<Object?> _connectorMessagesSub;
  late final StreamSubscription<String> _connectorTextSub;
  late final StreamSubscription<String> _transportTextSub;
  late final StreamSubscription<Object> _connectorErrorSub;

  final StreamController<String> _textController =
      StreamController<String>.broadcast();
  final StreamController<Object> _errorController =
      StreamController<Object>.broadcast();
  bool _isDisposed = false;

  /// Stream of conversational text chunks from the agent.
  Stream<String> get textStream => _textController.stream;

  /// Stream of transport or parsing errors.
  Stream<Object> get errorStream => _errorController.stream;

  /// Sends a [ChatMessage] through the [A2uiTransportAdapter].
  Future<void> sendMessage(ChatMessage message) {
    return _transportAdapter.sendRequest(message);
  }

  Future<Stream<String>> _onSendToConnector(ChatMessage message) async {
    final StreamController<String> responseStream = StreamController<String>();

    unawaited(
      _connector
          .connectAndSend(
            message,
            clientCapabilities: A2UiClientCapabilities(
              supportedCatalogIds: <String>[
                AppConfig.snapSellCatalogId,
                ...AppConfig.catalogIdAliases,
              ],
            ),
            clientDataModel: _collectClientDataModel(),
          )
          .then((String? text) {
            if (text != null && text.isNotEmpty && !responseStream.isClosed) {
              responseStream.add(text);
            }
          })
          .catchError((Object error, StackTrace stackTrace) {
            if (!_errorController.isClosed) {
              _errorController.add(error);
            }
            if (!responseStream.isClosed) {
              responseStream.addError(error, stackTrace);
            }
          })
          .whenComplete(() async {
            if (!responseStream.isClosed) {
              await responseStream.close();
            }
          }),
    );

    return responseStream.stream;
  }

  Map<String, Object?>? _collectClientDataModel() {
    final Map<String, Object?> snapshot = <String, Object?>{};
    for (final String surfaceId in surfaceController.registry.surfaceOrder) {
      final Object? rootValue = surfaceController
          .contextFor(surfaceId)
          .dataModel
          .getValue<Object?>(DataPath.root);
      if (rootValue != null) {
        snapshot[surfaceId] = rootValue;
      }
    }
    return snapshot.isEmpty ? null : snapshot;
  }

  /// Disposes subscriptions, transport adapter, connector, and surface controller.
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    _incomingMessagesSub.cancel();
    _connectorMessagesSub.cancel();
    _connectorTextSub.cancel();
    _transportTextSub.cancel();
    _connectorErrorSub.cancel();
    _textController.close();
    _errorController.close();
    _transportAdapter.dispose();
    _connector.dispose();
    surfaceController.dispose();
  }
}

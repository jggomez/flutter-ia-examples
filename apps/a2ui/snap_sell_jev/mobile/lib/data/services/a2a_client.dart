import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// MIME type of a DataPart carrying one A2UI v1.0 message.
const String a2uiMimeType = 'application/a2ui+json';

/// URI of the A2UI v1.0 A2A extension the agent advertises in its AgentCard.
const String a2uiExtensionUri = 'https://a2ui.org/a2a-extension/a2ui/v1.0';

/// A part of an A2A message (the v0.3 JSON shape, discriminated by `kind`).
sealed class A2aPart {
  const A2aPart();

  Map<String, Object?> toJson();

  static A2aPart? fromJson(Map<String, Object?> json) {
    final Map<String, Object?>? metadata = _map(json['metadata']);
    return switch (json['kind']) {
      'text' => A2aTextPart(json['text'] as String? ?? ''),
      'data' => A2aDataPart(_map(json['data']) ?? const {}, metadata: metadata),
      _ => null,
    };
  }
}

final class A2aTextPart extends A2aPart {
  const A2aTextPart(this.text);

  final String text;

  @override
  Map<String, Object?> toJson() => {'kind': 'text', 'text': text};
}

final class A2aDataPart extends A2aPart {
  const A2aDataPart(this.data, {this.metadata});

  /// A DataPart holding one A2UI message, tagged with [a2uiMimeType].
  const A2aDataPart.a2ui(this.data)
    : metadata = const {'mimeType': a2uiMimeType};

  final Map<String, Object?> data;
  final Map<String, Object?>? metadata;

  bool get isA2ui =>
      metadata?['mimeType'] == a2uiMimeType || data['version'] == '1.0';

  @override
  Map<String, Object?> toJson() => {
    'kind': 'data',
    'data': data,
    if (metadata != null) 'metadata': metadata,
  };
}

final class A2aFilePart extends A2aPart {
  const A2aFilePart({required this.bytes, required this.mimeType, this.name});

  final Uint8List bytes;
  final String mimeType;
  final String? name;

  @override
  Map<String, Object?> toJson() => {
    'kind': 'file',
    'file': {
      'bytes': base64Encode(bytes),
      'mimeType': mimeType,
      if (name != null) 'name': name,
    },
  };
}

/// One streamed A2A event, flattened to what the app needs.
class A2aEvent {
  const A2aEvent({
    required this.kind,
    required this.parts,
    this.contextId,
    this.taskId,
    this.state,
    this.isFinal = false,
  });

  /// `task`, `status-update`, `artifact-update` or `message`.
  final String kind;
  final String? contextId;
  final String? taskId;

  /// Task state (`working`, `completed`, `failed`...) when [kind] carries one.
  final String? state;
  final bool isFinal;
  final List<A2aPart> parts;

  bool get isFailure =>
      state == 'failed' || state == 'rejected' || state == 'canceled';

  static A2aEvent fromResult(Map<String, Object?> result) {
    final String kind = result['kind'] as String? ?? '';
    final Map<String, Object?>? status = _map(result['status']);
    final Map<String, Object?>? message = switch (kind) {
      'message' => result,
      _ => _map(status?['message']),
    };
    final List<Object?> rawParts = <Object?>[
      ...?(message?['parts'] as List<Object?>?),
      if (kind == 'artifact-update')
        ...?(_map(result['artifact'])?['parts'] as List<Object?>?),
    ];
    return A2aEvent(
      kind: kind,
      contextId: result['contextId'] as String?,
      taskId:
          (result['taskId'] ?? (kind == 'task' ? result['id'] : null))
              as String?,
      state: status?['state'] as String?,
      isFinal: result['final'] == true,
      parts: <A2aPart>[
        for (final Object? raw in rawParts)
          if (_map(raw) case final Map<String, Object?> json)
            ?A2aPart.fromJson(json),
      ],
    );
  }
}

class A2aException implements Exception {
  const A2aException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => 'A2aException: $message';
}

/// Minimal A2A client: JSON-RPC `message/stream` over Server-Sent Events.
///
/// Replaces `genui_a2a`, which is tied to the deprecated `genui` package.
/// Speaks the A2A v0.3 JSON shape the agent serves with
/// `enable_v0_3_compat=True`.
class A2aClient {
  A2aClient({
    required this.endpoint,
    http.Client? httpClient,
    this.headers = const {},
  }) : _http = httpClient ?? http.Client();

  final Uri endpoint;
  final http.Client _http;

  /// Extra headers sent with every request (for example an auth token).
  final Map<String, String> headers;
  int _nextId = 0;

  /// Sends a user message and yields every streamed event until the stream
  /// closes. Throws [A2aException] on HTTP or JSON-RPC errors.
  Stream<A2aEvent> sendMessage({
    required List<A2aPart> parts,
    String? contextId,
    Map<String, Object?>? metadata,
  }) async* {
    final String id = '${DateTime.now().microsecondsSinceEpoch}-${_nextId++}';
    final Map<String, Object?> request = {
      'jsonrpc': '2.0',
      'id': id,
      'method': 'message/stream',
      'params': {
        'message': {
          'kind': 'message',
          'messageId': 'msg-$id',
          'role': 'user',
          'parts': [for (final A2aPart p in parts) p.toJson()],
          'contextId': ?contextId,
          if (metadata != null && metadata.isNotEmpty) 'metadata': metadata,
          'extensions': [a2uiExtensionUri],
        },
      },
    };
    final http.Request httpRequest = http.Request('POST', endpoint)
      ..headers.addAll({
        'Content-Type': 'application/json',
        'Accept': 'text/event-stream',
        'X-A2A-Extensions': a2uiExtensionUri,
        ...headers,
      })
      ..body = jsonEncode(request);

    final http.StreamedResponse response;
    try {
      response = await _http.send(httpRequest);
    } on http.ClientException catch (e) {
      throw A2aException('Network error: ${e.message}');
    }
    if (response.statusCode >= 400) {
      final String body = await response.stream.bytesToString();
      throw A2aException(
        'HTTP ${response.statusCode}: $body',
        statusCode: response.statusCode,
      );
    }

    final StringBuffer data = StringBuffer();
    await for (final String line
        in response.stream
            .transform(utf8.decoder)
            .transform(const LineSplitter())) {
      if (line.startsWith('data:')) {
        data.write(line.substring(5).trimLeft());
        continue;
      }
      if (line.isNotEmpty || data.isEmpty) continue;
      final A2aEvent? event = _decode(data.toString());
      data.clear();
      if (event != null) yield event;
    }
    if (data.isNotEmpty) {
      final A2aEvent? event = _decode(data.toString());
      if (event != null) yield event;
    }
  }

  A2aEvent? _decode(String payload) {
    final Object? json = jsonDecode(payload);
    if (json is! Map<String, Object?>) return null;
    final Map<String, Object?>? error = _map(json['error']);
    if (error != null) {
      throw A2aException('JSON-RPC ${error['code']}: ${error['message']}');
    }
    final Map<String, Object?>? result = _map(json['result']);
    return result == null ? null : A2aEvent.fromResult(result);
  }

  void close() => _http.close();
}

Map<String, Object?>? _map(Object? value) =>
    value is Map ? value.cast<String, Object?>() : null;

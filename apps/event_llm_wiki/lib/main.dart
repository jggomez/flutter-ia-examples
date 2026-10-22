import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'app.dart';
import 'data/local/hive_boxes.dart';
import 'data/models/chat_message_dto.dart';
import 'data/repositories/agenda_repository_impl.dart';
import 'data/repositories/chat_engine_repository_impl.dart';
import 'data/repositories/chat_history_repository_impl.dart';
import 'data/repositories/model_download_repository_impl.dart';
import 'data/services/agenda_asset_service.dart';
import 'data/services/app_storage_service.dart';
import 'data/services/litert_lm_service.dart';
import 'data/services/model_download_service.dart';
import 'data/services/network_connectivity_service.dart';
import 'ui/providers/repository_providers.dart';

/// Download URL for `litert-community/Gemma3-1B-IT`'s `dynamic_int4`,
/// 4096-token-context `.litertlm` file (see
/// `doc/adr/0001-llm-runtime-model-selection.md`). Hard-coded here per that
/// ADR's "Consequences" section — there is no in-app model picker.
///
/// KNOWN ISSUE (flagged for follow-up, not silently worked around): as of
/// this implementation, this HuggingFace repository is gated behind the
/// Gemma license ("Access to model litert-community/Gemma3-1B-IT is
/// restricted... must be authenticated"), which `ModelDownloadService`
/// (a plain unauthenticated `http.Client` GET) cannot satisfy. A real
/// end-user download of this exact URL will fail with an HTTP 401 until
/// either an `Authorization: Bearer <token>` header is added to
/// `ModelDownloadServiceImpl`'s request (requiring this app to obtain and
/// store a HuggingFace token — a new, not-yet-made architectural decision),
/// or ADR 0001's model choice is revisited in favor of an ungated
/// `.litertlm` file. See the flutter-implementer hand-off report for the
/// on-device checkpoint evidence this was discovered from.
final _modelDownloadUrl = Uri.parse(
  'https://huggingface.co/litert-community/Gemma3-1B-IT/resolve/main/'
  'Gemma3-1B-IT_multi-prefill-seq_q4_ekv4096.litertlm',
);

/// Sync Hive bootstrap only — deliberately NO async model-download gate
/// here (unlike a hypothetical eager-download design). The model download
/// is lazy, triggered when the user opens the Chat tab (see
/// `doc/adr/0005-model-download-flow.md`); `main()` only needs Hive ready
/// before anything reads `chatHistoryRepositoryProvider`.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Hive: register `ChatMessageDto`'s generated adapter and open its box
  // before anything reads `chatHistoryRepositoryProvider` (see
  // doc/adr/0004-persistence-hive-chat-history.md and
  // `data/local/hive_boxes.dart` for the typeId/box-name registry this must
  // stay in sync with).
  await Hive.initFlutter();
  Hive.registerAdapter(ChatMessageDtoAdapter());
  final chatHistoryBox = await Hive.openBox<ChatMessageDto>(
    HiveBoxes.chatHistory,
  );

  final agendaRepository = AgendaRepositoryImpl(
    agendaAssetService: AgendaAssetServiceImpl(),
  );
  final appStorageService = AppStorageServiceImpl();
  // Resolved once at startup (not lazily inside a Provider body, which must
  // stay synchronous): by the time `ChatViewModel.build()` ever calls
  // `initialize()`, `ChatTabRoot` has already confirmed
  // `ModelDownloadPhase.ready` via `ModelDownloadViewModel`, so a validated
  // model file is guaranteed to exist at this path.
  final modelPath = await appStorageService.modelFilePath;

  runApp(
    ProviderScope(
      overrides: [
        // Real repositories, each composed from the real services (see
        // PLAN.md phases 5-8). Every `ui/features/**` view model depends on
        // these four abstractions only — see
        // `doc/adr/0003-state-management-riverpod.md`'s compliance rule.
        agendaRepositoryProvider.overrideWithValue(agendaRepository),
        chatEngineRepositoryProvider.overrideWithValue(
          ChatEngineRepositoryImpl(
            litertLmService: LitertLmServiceImpl(),
            modelPath: modelPath,
          ),
        ),
        chatHistoryRepositoryProvider.overrideWithValue(
          ChatHistoryRepositoryImpl(
            box: chatHistoryBox,
            agendaRepository: agendaRepository,
          ),
        ),
        modelDownloadRepositoryProvider.overrideWithValue(
          ModelDownloadRepositoryImpl(
            modelDownloadService: ModelDownloadServiceImpl(),
            appStorageService: appStorageService,
            networkConnectivityService: const NetworkConnectivityServiceImpl(),
            modelUrl: _modelDownloadUrl,
          ),
        ),
      ],
      child: const EventLlmWikiApp(),
    ),
  );
}

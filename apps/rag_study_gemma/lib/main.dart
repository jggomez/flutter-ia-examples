import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'app.dart';
import 'data/local/hive_boxes.dart';
import 'data/models/chat_message_dto.dart';
import 'data/models/study_document_dto.dart';
import 'data/repositories/chat_engine_repository_impl.dart';
import 'data/repositories/chat_history_repository_impl.dart';
import 'data/repositories/document_ingestion_repository_impl.dart';
import 'data/repositories/model_download_repository_impl.dart';
import 'data/repositories/rag_index_repository_impl.dart';
import 'data/services/app_storage_service.dart';
import 'data/services/edge_ai_rag_service.dart';
import 'data/services/model_download_service.dart';
import 'data/services/network_connectivity_service.dart';
import 'data/services/pdf_extractor_service.dart';
import 'data/services/pdf_picker_service.dart';
import 'ui/providers/repository_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Hive.initFlutter();
  if (!Hive.isAdapterRegistered(HiveTypeIds.studyDocumentDto)) {
    Hive.registerAdapter(StudyDocumentDtoAdapter());
  }
  if (!Hive.isAdapterRegistered(HiveTypeIds.chatMessageDto)) {
    Hive.registerAdapter(ChatMessageDtoAdapter());
  }

  final documentsBox = await Hive.openBox<StudyDocumentDto>(
    HiveBoxes.documents,
  );
  final chatHistoryBox = await Hive.openBox<ChatMessageDto>(
    HiveBoxes.chatHistory,
  );

  final appStorageService = AppStorageServiceImpl();
  final edgeAiRagService = EdgeAiRagServiceImpl();
  const pdfPickerService = PdfPickerServiceImpl();
  const pdfExtractorService = PdfExtractorServiceImpl();
  final modelDownloadService = ModelDownloadServiceImpl();
  const networkConnectivityService = NetworkConnectivityServiceImpl();

  final ragIndexRepository = RagIndexRepositoryImpl(
    edgeAiRagService: edgeAiRagService,
    appStorageService: appStorageService,
  );
  final documentIngestionRepository = DocumentIngestionRepositoryImpl(
    ragIndexRepository: ragIndexRepository,
    documentsBox: documentsBox,
    pdfPickerService: pdfPickerService,
    pdfExtractorService: pdfExtractorService,
  );
  final chatEngineRepository = ChatEngineRepositoryImpl(
    edgeAiRagService: edgeAiRagService,
    appStorageService: appStorageService,
  );
  final chatHistoryRepository = ChatHistoryRepositoryImpl(box: chatHistoryBox);
  final modelDownloadRepository = ModelDownloadRepositoryImpl(
    appStorageService: appStorageService,
    networkConnectivityService: networkConnectivityService,
    modelDownloadService: modelDownloadService,
  );

  runApp(
    ProviderScope(
      overrides: [
        ragIndexRepositoryProvider.overrideWithValue(ragIndexRepository),
        documentIngestionRepositoryProvider.overrideWithValue(
          documentIngestionRepository,
        ),
        chatEngineRepositoryProvider.overrideWithValue(chatEngineRepository),
        chatHistoryRepositoryProvider.overrideWithValue(chatHistoryRepository),
        modelDownloadRepositoryProvider.overrideWithValue(
          modelDownloadRepository,
        ),
      ],
      child: const StudyGemmaApp(),
    ),
  );
}

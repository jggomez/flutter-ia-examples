import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'app.dart';
import 'data/local/hive_boxes.dart';
import 'data/models/match_record_dto.dart';
import 'data/repositories/classifier_repository_impl.dart';
import 'data/repositories/history_repository_impl.dart';
import 'data/services/camera_frame_service.dart';
import 'data/services/tflite_classifier_service.dart';
import 'ui/providers/repository_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Hive: register `MatchRecordDto`'s generated adapter and open its box
  // before anything reads `historyRepositoryProvider` (see
  // doc/adr/0002-persistence-hive.md and `data/local/hive_boxes.dart` for
  // the typeId/box-name registry this must stay in sync with).
  await Hive.initFlutter();
  Hive.registerAdapter(MatchRecordDtoAdapter());
  final matchHistoryBox = await Hive.openBox<MatchRecordDto>(
    HiveBoxes.matchHistory,
  );

  runApp(
    ProviderScope(
      overrides: [
        // Real `ClassifierRepository`, composed from the real camera +
        // interpreter services (see `ClassifierRepositoryImpl`'s doc
        // comment for the isolate/throttling strategy). Every
        // `ui/features/**` view model depends on the abstraction only.
        classifierRepositoryProvider.overrideWithValue(
          ClassifierRepositoryImpl(
            cameraFrameService: CameraFrameServiceImpl(),
            classifierService: TfliteClassifierServiceImpl(),
          ),
        ),
        historyRepositoryProvider.overrideWithValue(
          HistoryRepositoryImpl(box: matchHistoryBox),
        ),
      ],
      child: const RpsLiveApp(),
    ),
  );
}

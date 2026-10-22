import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genui/genui.dart';
import 'package:mobile/src/catalog/snap_sell_catalog.dart';
import 'package:mobile/src/data/image_capture_service.dart';

class _RecordingImageCaptureService implements ImageCaptureService {
  PhotoCaptureSource? lastSource;
  double? lastMaxWidth;
  double? lastMaxHeight;
  int? lastImageQuality;
  CapturedPhoto? nextPhoto;
  final List<CapturedPhoto> queuedPhotos = <CapturedPhoto>[];

  @override
  Future<CapturedPhoto?> capturePhoto(
    PhotoCaptureSource source, {
    double maxWidth = 1024,
    double maxHeight = 1024,
    int imageQuality = 82,
  }) async {
    lastSource = source;
    lastMaxWidth = maxWidth;
    lastMaxHeight = maxHeight;
    lastImageQuality = imageQuality;
    return nextPhoto;
  }

  @override
  void queueFollowupPhoto(CapturedPhoto photo) {
    queuedPhotos.add(photo);
  }

  @override
  CapturedPhoto? takeQueuedFollowupPhoto() {
    if (queuedPhotos.isEmpty) return null;
    return queuedPhotos.removeAt(0);
  }
}

void main() {
  group('PhotoRequest catalog widget', () {
    late SurfaceController controller;
    late _RecordingImageCaptureService captureService;

    setUp(() {
      captureService = _RecordingImageCaptureService()
        ..nextPhoto = CapturedPhoto(
          bytes: _kSamplePng,
          mimeType: 'image/jpeg',
          fileName: 'odometer.jpg',
          source: PhotoCaptureSource.camera,
        );
      controller = SurfaceController(
        catalogs: <Catalog>[
          buildSnapSellCatalog(imageCaptureService: captureService),
        ],
      );
    });

    tearDown(() {
      controller.dispose();
    });

    testWidgets(
      'invokes ImageCaptureService, updates DataModel to uploaded, queues bytes, and dispatches action',
      (WidgetTester tester) async {
        final List<ChatMessage> submittedMessages = <ChatMessage>[];
        final subscription = controller.onSubmit.listen(submittedMessages.add);
        addTearDown(subscription.cancel);

        feedA2uiJson(controller, <Map<String, Object?>>[
          <String, Object?>{
            'version': 'v0.9',
            'createSurface': <String, Object?>{
              'surfaceId': 'step_2',
              'catalogId': 'https://snap-sell.devhack.dev/a2ui/v0.9/snap_sell_catalog.json',
              'sendDataModel': true,
            },
          },
          <String, Object?>{
            'version': 'v0.9',
            'updateDataModel': <String, Object?>{
              'surfaceId': 'step_2',
              'path': '/',
              'value': <String, Object?>{
                'followup': <String, Object?>{'odometerPhotoUrl': ''},
              },
            },
          },
          <String, Object?>{
            'version': 'v0.9',
            'updateComponents': <String, Object?>{
              'surfaceId': 'step_2',
              'components': <Map<String, Object?>>[
                <String, Object?>{
                  'id': 'root',
                  'component': 'PhotoRequest',
                  'requestType': 'odometer',
                  'requestId': 'req_odo_1',
                  'title': 'Odometer Photo',
                  'instructions': 'Snap a clear photo of the odometer.',
                  'actionName': 'submit_followup_photo',
                  'targetPath': '/followup/odometerPhotoUrl',
                  'photoStatusPath': '/followup/odometerStatus',
                  'required': true,
                },
              ],
            },
          },
        ]);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Surface(surfaceContext: controller.contextFor('step_2')),
            ),
          ),
        );
        await tester.pump();

        expect(find.text('Odometer Photo'), findsOneWidget);
        expect(
          find.text('Snap a clear photo of the odometer.'),
          findsOneWidget,
        );
        expect(find.textContaining('ODOMETER'), findsOneWidget);

        await tester.tap(find.text('Take Photo'));
        await tester.pumpAndSettle();

        expect(captureService.lastSource, equals(PhotoCaptureSource.camera));
        expect(captureService.lastMaxWidth, equals(1024));
        expect(captureService.lastMaxHeight, equals(1024));
        expect(captureService.lastImageQuality, equals(82));
        expect(captureService.queuedPhotos, hasLength(1));

        final DataModel dataModel = controller.contextFor('step_2').dataModel;
        expect(
          dataModel.getValue<String>(DataPath('/followup/odometerPhotoUrl')),
          equals('uploaded'),
        );
        expect(
          dataModel.getValue<String>(DataPath('/followup/odometerStatus')),
          equals('uploaded'),
        );

        expect(submittedMessages, hasLength(1));
        final UiInteractionPart interactionPart =
            submittedMessages.first.parts.uiInteractionParts.first;
        final Map<String, Object?> payload =
            jsonDecode(interactionPart.interaction) as Map<String, Object?>;
        final Map<String, Object?> action =
            payload['action'] as Map<String, Object?>;
        expect(action['name'], equals('submit_followup_photo'));
        final Map<String, Object?> ctx =
            action['context'] as Map<String, Object?>;
        expect(ctx['target'], equals('odometer'));
        expect(ctx['requestType'], equals('odometer'));
        expect(ctx['requestId'], equals('req_odo_1'));
      },
    );
  });
}

final Uint8List _kSamplePng = Uint8List.fromList(<int>[
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x06,
  0x00,
  0x00,
  0x00,
  0x1F,
  0x15,
  0xC4,
  0x89,
  0x00,
  0x00,
  0x00,
  0x0A,
  0x49,
  0x44,
  0x41,
  0x54,
  0x78,
  0x9C,
  0x63,
  0x00,
  0x01,
  0x00,
  0x00,
  0x05,
  0x00,
  0x01,
  0x0D,
  0x0A,
  0x2D,
  0xB4,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4E,
  0x44,
  0xAE,
  0x42,
  0x60,
  0x82,
]);

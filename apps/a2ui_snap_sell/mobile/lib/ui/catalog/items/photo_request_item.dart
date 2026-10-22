import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:genui/genui.dart';
import 'package:json_schema_builder/json_schema_builder.dart';

import '../../../domain/repositories/image_capture_repository.dart';
import 'data_context_binding_ext.dart';

final Schema _schema = S.object(
  description: 'Prompts the seller to capture a follow-up photo (damage, odometer, or extra angle).',
  properties: <String, Schema>{
    'requestType': S.string(
      enumValues: <String>['damage', 'odometer', 'extra', 'id_label', 'angle'],
    ),
    'requestId': S.string(),
    'target': S.string(),
    'title': A2uiSchemas.stringReference(),
    'instructions': A2uiSchemas.stringReference(),
    'actionName': S.string(),
    'targetPath': S.string(),
    'photoStatusPath': S.string(),
    'previewUrl': A2uiSchemas.stringReference(),
    'required': S.boolean(),
  },
  required: <String>[
    'requestType',
    'title',
    'instructions',
    'actionName',
    'targetPath',
  ],
);

/// Callback invoked when `PhotoRequest` delegates photo capture to a session controller.
typedef PhotoRequestCaptureCallback = Future<CapturedPhoto?> Function({
  required String requestType,
  required String actionName,
  required String targetPath,
  required PhotoCaptureSource source,
  String? requestId,
});

/// Builds the `PhotoRequest` catalog item with injected capture dependencies.
CatalogItem buildPhotoRequestCatalogItem({
  ImageCaptureRepository? imageCaptureService,
  PhotoRequestCaptureCallback? onCapturePhotoRequested,
}) {
  return CatalogItem(
    name: 'PhotoRequest',
    dataSchema: _schema,
    widgetBuilder: (CatalogItemContext itemContext) {
      final JsonMap json = itemContext.data as JsonMap;
      final String requestType =
          (json['requestType'] as String?) ??
          (json['target'] as String?) ??
          'extra';
      final String? requestId = json['requestId'] as String?;
      final String actionName =
          (json['actionName'] as String?) ?? 'submit_followup_photo';
      final String targetPath =
          (json['targetPath'] as String?) ?? '/followup/$requestType';
      final String? photoStatusPath = json['photoStatusPath'] as String?;
      final bool isRequired = (json['required'] as bool?) ?? true;

      final ValueListenable<String?> titleNotifier = itemContext.dataContext
          .subscribeToString(json['title']);
      final ValueListenable<String?> instructionsNotifier = itemContext
          .dataContext
          .subscribeToString(json['instructions']);
      final ValueListenable<String?> previewUrlNotifier = itemContext
          .dataContext
          .subscribeToString(json['previewUrl']);
      final ValueListenable<String?> targetValueNotifier = itemContext
          .dataContext
          .subscribeToValue<String>(DataPath(targetPath));

      return _PhotoRequestWidget(
        componentId: itemContext.id,
        surfaceId: itemContext.surfaceId,
        requestType: requestType,
        requestId: requestId,
        actionName: actionName,
        targetPath: targetPath,
        photoStatusPath: photoStatusPath,
        isRequired: isRequired,
        titleNotifier: titleNotifier,
        instructionsNotifier: instructionsNotifier,
        previewUrlNotifier: previewUrlNotifier,
        targetValueNotifier: targetValueNotifier,
        dataContext: itemContext.dataContext,
        dispatchEvent: itemContext.dispatchEvent,
        imageCaptureService: imageCaptureService,
        onCapturePhotoRequested: onCapturePhotoRequested,
      );
    },
  );
}

/// Default `PhotoRequest` catalog item instance.
final CatalogItem photoRequestItem = buildPhotoRequestCatalogItem();

class _PhotoRequestWidget extends StatefulWidget {
  const _PhotoRequestWidget({
    required this.componentId,
    required this.surfaceId,
    required this.requestType,
    required this.requestId,
    required this.actionName,
    required this.targetPath,
    required this.photoStatusPath,
    required this.isRequired,
    required this.titleNotifier,
    required this.instructionsNotifier,
    required this.previewUrlNotifier,
    required this.targetValueNotifier,
    required this.dataContext,
    required this.dispatchEvent,
    this.imageCaptureService,
    this.onCapturePhotoRequested,
  });

  final String componentId;
  final String surfaceId;
  final String requestType;
  final String? requestId;
  final String actionName;
  final String targetPath;
  final String? photoStatusPath;
  final bool isRequired;
  final ValueListenable<String?> titleNotifier;
  final ValueListenable<String?> instructionsNotifier;
  final ValueListenable<String?> previewUrlNotifier;
  final ValueListenable<String?> targetValueNotifier;
  final DataContext dataContext;
  final DispatchEventCallback dispatchEvent;
  final ImageCaptureRepository? imageCaptureService;
  final PhotoRequestCaptureCallback? onCapturePhotoRequested;

  @override
  State<_PhotoRequestWidget> createState() => _PhotoRequestWidgetState();
}

class _PhotoRequestWidgetState extends State<_PhotoRequestWidget> {
  Uint8List? _capturedBytes;
  bool _isCapturing = false;

  IconData _requestIcon() {
    switch (widget.requestType.toLowerCase()) {
      case 'damage':
        return Icons.report_problem_outlined;
      case 'odometer':
        return Icons.speed;
      default:
        return Icons.add_a_photo_outlined;
    }
  }

  Future<void> _handleCapture(PhotoCaptureSource source) async {
    if (_isCapturing) return;
    setState(() {
      _isCapturing = true;
    });

    try {
      CapturedPhoto? photo;
      if (widget.imageCaptureService != null) {
        photo = await widget.imageCaptureService!.capturePhoto(
          source,
          maxWidth: 1024,
          maxHeight: 1024,
          imageQuality: 82,
        );
        if (photo != null) {
          widget.imageCaptureService!.queueFollowupPhoto(photo);
        }
      } else if (widget.onCapturePhotoRequested != null) {
        photo = await widget.onCapturePhotoRequested!(
          requestType: widget.requestType,
          actionName: widget.actionName,
          targetPath: widget.targetPath,
          source: source,
          requestId: widget.requestId,
        );
      }

      if (!mounted) return;
      if (photo == null) return;

      setState(() {
        _capturedBytes = photo!.bytes;
      });

      widget.dataContext.update(DataPath(widget.targetPath), 'uploaded');
      if (widget.photoStatusPath != null &&
          widget.photoStatusPath!.isNotEmpty) {
        widget.dataContext.update(
          DataPath(widget.photoStatusPath!),
          'uploaded',
        );
      }

      widget.dispatchEvent(
        UserActionEvent(
          name: widget.actionName,
          sourceComponentId: widget.componentId,
          surfaceId: widget.surfaceId,
          context: <String, Object?>{
            'target': widget.requestType,
            'requestType': widget.requestType,
            'targetPath': widget.targetPath,
            'status': 'uploaded',
            if (widget.requestId != null) 'requestId': widget.requestId,
          },
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isCapturing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;

    return Semantics(
      container: true,
      label: 'Photo request: ${widget.requestType.toUpperCase()}',
      child: Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(_requestIcon(), color: colorScheme.primary, size: 20),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      widget.requestType.toUpperCase(),
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (widget.isRequired)
                    Text(
                      'Required',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.error,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  const Spacer(),
                  ValueListenableBuilder<String?>(
                    valueListenable: widget.targetValueNotifier,
                    builder:
                        (BuildContext context, String? statusVal, Widget? _) {
                          final bool isUploaded =
                              _capturedBytes != null ||
                              (statusVal != null && statusVal.isNotEmpty);
                          if (!isUploaded) {
                            return const SizedBox.shrink();
                          }
                          return Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Icon(
                                Icons.check_circle,
                                size: 16,
                                color: colorScheme.primary,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Uploaded',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: colorScheme.primary,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          );
                        },
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ValueListenableBuilder<String?>(
                valueListenable: widget.titleNotifier,
                builder: (BuildContext context, String? title, Widget? _) {
                  return Text(
                    title ?? 'Follow-up Photo',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  );
                },
              ),
              const SizedBox(height: 4),
              ValueListenableBuilder<String?>(
                valueListenable: widget.instructionsNotifier,
                builder:
                    (BuildContext context, String? instructions, Widget? _) {
                      if (instructions == null || instructions.isEmpty) {
                        return const SizedBox.shrink();
                      }
                      return Text(
                        instructions,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      );
                    },
              ),
              if (_capturedBytes != null) ...<Widget>[
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.memory(
                    _capturedBytes!,
                    height: 110,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder:
                        (BuildContext context, Object e, StackTrace? _) {
                          return const SizedBox.shrink();
                        },
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: <Widget>[
                  FilledButton.icon(
                    onPressed: _isCapturing
                        ? null
                        : () => _handleCapture(PhotoCaptureSource.camera),
                    icon: const Icon(Icons.camera_alt_outlined, size: 18),
                    label: const Text('Take Photo'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _isCapturing
                        ? null
                        : () => _handleCapture(PhotoCaptureSource.gallery),
                    icon: const Icon(Icons.photo_library_outlined, size: 18),
                    label: const Text('Gallery'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

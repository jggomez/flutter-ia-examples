import 'dart:typed_data';

import 'package:a2ui_core/a2ui_core.dart';
import 'package:a2ui_flutter/a2ui_flutter.dart';
import 'package:flutter/material.dart';

import '../../../domain/repositories/image_capture_repository.dart';
import '../snap_sell_catalog.dart';

typedef PhotoRequestCaptureCallback = Future<CapturedPhoto?> Function({
  required String requestType,
  required String actionName,
  required String targetPath,
  required PhotoCaptureSource source,
  String? requestId,
});

/// Called after a photo is captured: marks [targetPath] as uploaded and emits
/// the agent-bound action.
typedef PhotoUploadedCallback = Future<void> Function({
  required String actionName,
  required String targetPath,
  required Map<String, Object?> actionContext,
});

/// `PhotoRequest`: asks the seller for a follow-up photo (damage, odometer...).
ComponentImplementation buildPhotoRequestComponent({
  ImageCaptureRepository? imageCaptureService,
  PhotoRequestCaptureCallback? onCapturePhotoRequested,
}) {
  return implementContractComponent('PhotoRequest', (
    BuildContext context,
    ComponentNode<ComponentImplementation> node,
    ComponentProps props,
    ChildWidgetBuilder buildChild,
  ) {
    final String requestType = props.string('requestType') ?? 'extra';
    return PhotoRequestCard(
      key: NodeKey(node.instanceId),
      requestType: requestType,
      requestId: props.string('requestId'),
      title: props.string('title'),
      instructions: props.string('instructions'),
      actionName: props.string('actionName') ?? 'submit_followup_photo',
      targetPath: props.string('targetPath') ?? '/followup/$requestType',
      isRequired: props.boolean('required') ?? true,
      imageCaptureService: imageCaptureService,
      onCapturePhotoRequested: onCapturePhotoRequested,
      onUploaded:
          ({
            required String actionName,
            required String targetPath,
            required Map<String, Object?> actionContext,
          }) {
            node.writeData(targetPath, 'uploaded');
            return node.emitAction(actionName, actionContext);
          },
    );
  });
}

final ComponentImplementation photoRequestComponent =
    buildPhotoRequestComponent();

class PhotoRequestCard extends StatefulWidget {
  const PhotoRequestCard({
    super.key,
    required this.requestType,
    required this.actionName,
    required this.targetPath,
    required this.onUploaded,
    this.requestId,
    this.title,
    this.instructions,
    this.isRequired = true,
    this.imageCaptureService,
    this.onCapturePhotoRequested,
  });

  final String requestType;
  final String? requestId;
  final String? title;
  final String? instructions;
  final String actionName;
  final String targetPath;
  final bool isRequired;
  final ImageCaptureRepository? imageCaptureService;
  final PhotoRequestCaptureCallback? onCapturePhotoRequested;
  final PhotoUploadedCallback onUploaded;

  @override
  State<PhotoRequestCard> createState() => _PhotoRequestCardState();
}

class _PhotoRequestCardState extends State<PhotoRequestCard> {
  Uint8List? _capturedBytes;
  bool _isCapturing = false;

  IconData _requestIcon() => switch (widget.requestType.toLowerCase()) {
    'damage' => Icons.report_problem_outlined,
    'odometer' => Icons.speed,
    _ => Icons.add_a_photo_outlined,
  };

  Future<void> _handleCapture(PhotoCaptureSource source) async {
    if (_isCapturing) return;
    setState(() => _isCapturing = true);
    try {
      CapturedPhoto? photo;
      final ImageCaptureRepository? service = widget.imageCaptureService;
      if (service != null) {
        photo = await service.capturePhoto(
          source,
          maxWidth: 1024,
          maxHeight: 1024,
          imageQuality: 82,
        );
        // The repository attaches the queued photo to the next agent message.
        if (photo != null) service.queueFollowupPhoto(photo);
      } else if (widget.onCapturePhotoRequested != null) {
        photo = await widget.onCapturePhotoRequested!(
          requestType: widget.requestType,
          actionName: widget.actionName,
          targetPath: widget.targetPath,
          source: source,
          requestId: widget.requestId,
        );
      }
      if (!mounted || photo == null) return;
      setState(() => _capturedBytes = photo!.bytes);

      await widget.onUploaded(
        actionName: widget.actionName,
        targetPath: widget.targetPath,
        actionContext: <String, Object?>{
          'target': widget.requestType,
          'requestType': widget.requestType,
          'targetPath': widget.targetPath,
          'status': 'uploaded',
          if (widget.requestId != null) 'requestId': widget.requestId,
        },
      );
    } finally {
      if (mounted) setState(() => _isCapturing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    final String? instructions = widget.instructions;

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
                  if (_capturedBytes != null)
                    Row(
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
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                widget.title ?? 'Follow-up Photo',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (instructions != null && instructions.isNotEmpty) ...<Widget>[
                const SizedBox(height: 4),
                Text(
                  instructions,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              if (_capturedBytes != null) ...<Widget>[
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.memory(
                    _capturedBytes!,
                    height: 110,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (
                      BuildContext context,
                      Object e,
                      StackTrace? _,
                    ) => const SizedBox.shrink(),
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

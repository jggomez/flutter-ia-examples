import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:genui/genui.dart';
import 'package:json_schema_builder/json_schema_builder.dart';

import 'data_context_binding_ext.dart';

final Schema _fieldItemSchema = S.object(
  properties: <String, Schema>{
    'key': S.string(),
    'label': S.string(),
    'value': A2uiSchemas.stringReference(),
    'valuePath': S.string(),
    'editable': S.boolean(),
  },
  required: <String>['key', 'label', 'value'],
);

final Schema _schema = S.object(
  description: 'Displays AI-detected item category, confidence, EV status, and editable attributes.',
  properties: <String, Schema>{
    'category': S.string(enumValues: <String>['car', 'motorcycle', 'phone']),
    'imageUrl': A2uiSchemas.stringReference(
      description: 'Reference or URL to the analyzed item image.',
    ),
    'confidence': S.number(minimum: 0.0, maximum: 1.0),
    'summary': A2uiSchemas.stringReference(
      description: 'Human-readable summary of the detected item.',
    ),
    'isEv': A2uiSchemas.booleanReference(
      description: 'Whether the vehicle is electric.',
    ),
    'fields': S.list(items: _fieldItemSchema, minItems: 1),
  },
  required: <String>['category', 'imageUrl', 'confidence', 'summary', 'fields'],
);

/// Builds the `DetectedItemCard` catalog item with optional in-memory photo cache.
CatalogItem buildDetectedItemCardCatalogItem({
  Map<String, Uint8List>? localPhotos,
}) {
  return CatalogItem(
    name: 'DetectedItemCard',
    dataSchema: _schema,
    widgetBuilder: (CatalogItemContext itemContext) {
      final JsonMap json = itemContext.data as JsonMap;
      final String category = (json['category'] as String?) ?? 'car';
      final double confidence = (json['confidence'] as num?)?.toDouble() ?? 0.0;
      final ValueListenable<String?> imageUrlNotifier = itemContext.dataContext
          .subscribeToString(json['imageUrl']);
      final ValueListenable<String?> summaryNotifier = itemContext.dataContext
          .subscribeToString(json['summary']);
      final ValueListenable<bool?> isEvNotifier = itemContext.dataContext
          .subscribeToBool(json['isEv']);

      final List<Object?> rawFields =
          (json['fields'] as List<Object?>?) ?? const <Object?>[];
      final List<_DetectedFieldConfig> fields = rawFields
          .whereType<Map<Object?, Object?>>()
          .map((Map<Object?, Object?> raw) {
            final String key = (raw['key'] ?? '').toString();
            final String label = (raw['label'] ?? key).toString();
            final Object? valueDef = raw['value'];
            final String? explicitPath = raw['valuePath'] as String?;
            String? boundPath = explicitPath;
            if (boundPath == null &&
                valueDef is Map &&
                valueDef['path'] is String) {
              boundPath = valueDef['path'] as String;
            }
            final bool editable = (raw['editable'] as bool?) ?? true;
            final ValueListenable<String?> notifier = itemContext.dataContext
                .subscribeToString(
                  valueDef ??
                      (boundPath != null
                          ? <String, Object?>{'path': boundPath}
                          : ''),
                );
            return _DetectedFieldConfig(
              key: key,
              label: label,
              boundPath: boundPath,
              editable: editable,
              valueNotifier: notifier,
            );
          })
          .toList(growable: false);

      return _DetectedItemCardWidget(
        category: category,
        confidence: confidence,
        imageUrlNotifier: imageUrlNotifier,
        summaryNotifier: summaryNotifier,
        isEvNotifier: isEvNotifier,
        fields: fields,
        dataContext: itemContext.dataContext,
        localPhotos: localPhotos,
      );
    },
  );
}

/// Default `DetectedItemCard` catalog item instance.
final CatalogItem detectedItemCardItem = buildDetectedItemCardCatalogItem();

class _DetectedFieldConfig {
  const _DetectedFieldConfig({
    required this.key,
    required this.label,
    required this.boundPath,
    required this.editable,
    required this.valueNotifier,
  });

  final String key;
  final String label;
  final String? boundPath;
  final bool editable;
  final ValueListenable<String?> valueNotifier;
}

class _DetectedItemCardWidget extends StatelessWidget {
  const _DetectedItemCardWidget({
    required this.category,
    required this.confidence,
    required this.imageUrlNotifier,
    required this.summaryNotifier,
    required this.isEvNotifier,
    required this.fields,
    required this.dataContext,
    this.localPhotos,
  });

  final String category;
  final double confidence;
  final ValueListenable<String?> imageUrlNotifier;
  final ValueListenable<String?> summaryNotifier;
  final ValueListenable<bool?> isEvNotifier;
  final List<_DetectedFieldConfig> fields;
  final DataContext dataContext;
  final Map<String, Uint8List>? localPhotos;

  IconData _categoryIcon() {
    switch (category.toLowerCase()) {
      case 'car':
        return Icons.directions_car_filled;
      case 'motorcycle':
        return Icons.two_wheeler;
      case 'phone':
        return Icons.smartphone;
      default:
        return Icons.inventory_2_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    final int confidencePercent = (confidence.clamp(0.0, 1.0) * 100).round();

    return Semantics(
      container: true,
      label: 'Detected item: ${category.toUpperCase()}, $confidencePercent%',
      child: Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ValueListenableBuilder<String?>(
                valueListenable: imageUrlNotifier,
                builder: (BuildContext context, String? imageUrl, Widget? _) {
                  return _DetectedPhotoHeader(
                    imageUrl: imageUrl,
                    localPhotos: localPhotos,
                    categoryIcon: _categoryIcon(),
                  );
                },
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: <Widget>[
                  Chip(
                    avatar: Icon(_categoryIcon(), size: 16),
                    label: Text(
                      category.toUpperCase(),
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                  Chip(
                    avatar: const Icon(Icons.auto_awesome, size: 16),
                    label: Text(
                      '$confidencePercent% confidence',
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    backgroundColor: colorScheme.secondaryContainer,
                    visualDensity: VisualDensity.compact,
                  ),
                  ValueListenableBuilder<bool?>(
                    valueListenable: isEvNotifier,
                    builder: (BuildContext context, bool? isEv, Widget? _) {
                      if (isEv != true) {
                        return const SizedBox.shrink();
                      }
                      return Chip(
                        avatar: const Icon(Icons.electric_bolt, size: 16),
                        label: Text(
                          'EV',
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        backgroundColor: colorScheme.tertiaryContainer,
                        visualDensity: VisualDensity.compact,
                      );
                    },
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ValueListenableBuilder<String?>(
                valueListenable: summaryNotifier,
                builder: (BuildContext context, String? summary, Widget? _) {
                  if (summary == null || summary.isEmpty) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      summary,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  );
                },
              ),
              for (final _DetectedFieldConfig field in fields)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _DetectedFieldInput(
                    config: field,
                    dataContext: dataContext,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetectedPhotoHeader extends StatelessWidget {
  const _DetectedPhotoHeader({
    required this.imageUrl,
    required this.localPhotos,
    required this.categoryIcon,
  });

  final String? imageUrl;
  final Map<String, Uint8List>? localPhotos;
  final IconData categoryIcon;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    Uint8List? bytes;
    if (localPhotos != null) {
      if (imageUrl != null && localPhotos!.containsKey(imageUrl)) {
        bytes = localPhotos![imageUrl];
      } else if (localPhotos!.containsKey('initial')) {
        bytes = localPhotos!['initial'];
      }
    }

    if (bytes != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.memory(
          bytes,
          height: 140,
          width: double.infinity,
          fit: BoxFit.cover,
          errorBuilder: (BuildContext context, Object error, StackTrace? _) {
            return _placeholder(colorScheme);
          },
        ),
      );
    }

    return _placeholder(colorScheme);
  }

  Widget _placeholder(ColorScheme colorScheme) {
    return Container(
      height: 96,
      width: double.infinity,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      alignment: Alignment.center,
      child: Icon(categoryIcon, size: 40, color: colorScheme.primary),
    );
  }
}

class _DetectedFieldInput extends StatefulWidget {
  const _DetectedFieldInput({required this.config, required this.dataContext});

  final _DetectedFieldConfig config;
  final DataContext dataContext;

  @override
  State<_DetectedFieldInput> createState() => _DetectedFieldInputState();
}

class _DetectedFieldInputState extends State<_DetectedFieldInput> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.config.valueNotifier.value ?? '',
    );
    widget.config.valueNotifier.addListener(_onExternalChange);
  }

  @override
  void didUpdateWidget(covariant _DetectedFieldInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.config.valueNotifier != widget.config.valueNotifier) {
      oldWidget.config.valueNotifier.removeListener(_onExternalChange);
      final String nextValue = widget.config.valueNotifier.value ?? '';
      if (_controller.text != nextValue) {
        _controller.text = nextValue;
      }
      widget.config.valueNotifier.addListener(_onExternalChange);
    }
  }

  void _onExternalChange() {
    final String nextValue = widget.config.valueNotifier.value ?? '';
    if (_controller.text != nextValue) {
      _controller.value = _controller.value.copyWith(
        text: nextValue,
        selection: TextSelection.collapsed(offset: nextValue.length),
      );
    }
  }

  @override
  void dispose() {
    widget.config.valueNotifier.removeListener(_onExternalChange);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      enabled: widget.config.editable,
      decoration: InputDecoration(
        labelText: widget.config.label,
        isDense: true,
      ),
      onChanged: (String newValue) {
        final String? path = widget.config.boundPath;
        if (path != null && path.isNotEmpty) {
          widget.dataContext.update(DataPath(path), newValue);
        }
      },
    );
  }
}

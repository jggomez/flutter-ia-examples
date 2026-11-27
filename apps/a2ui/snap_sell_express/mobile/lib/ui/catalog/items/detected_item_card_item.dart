import 'dart:typed_data';

import 'package:a2ui_core/a2ui_core.dart';
import 'package:a2ui_flutter/a2ui_flutter.dart';
import 'package:flutter/material.dart';

import '../snap_sell_catalog.dart';

/// One editable attribute of a detected item.
class DetectedField {
  const DetectedField({
    required this.key,
    required this.label,
    required this.value,
    required this.editable,
    this.onChanged,
  });

  final String key;
  final String label;
  final String value;
  final bool editable;

  /// Writes the edited value to the data path the field is bound to, or null
  /// when the value is a literal.
  final ValueChanged<String>? onChanged;
}

/// Reads a `fields` entry whose `value` is a `DynamicString`.
///
/// The binder resolves `{"@path": ...}` inside array items to a
/// [WritableBinding]; a literal string stays read-only.
DetectedField detectedFieldFromProp(
  Object? raw,
  ComponentNode<ComponentImplementation> node,
) {
  final Map<Object?, Object?> item = raw is Map ? raw : const {};
  final String key = (item['key'] ?? '').toString();
  final Object? value = item['value'];
  ValueChanged<String>? onChanged;
  if (value is WritableBinding<Object?>) {
    onChanged = value.set;
  } else if (value is Map && value['@path'] is String) {
    final String path = value['@path'] as String;
    onChanged = (String v) => node.writeData(path, v);
  }
  return DetectedField(
    key: key,
    label: (item['label'] ?? key).toString(),
    value: ComponentProps.asString(value) ?? '',
    editable: (item['editable'] as bool?) ?? true,
    onChanged: onChanged,
  );
}

/// `DetectedItemCard`: what Gemini detected in the photo, with editable fields.
ComponentImplementation buildDetectedItemCardComponent({
  Map<String, Uint8List>? localPhotos,
}) {
  return implementContractComponent('DetectedItemCard', (
    BuildContext context,
    ComponentNode<ComponentImplementation> node,
    ComponentProps props,
    ChildWidgetBuilder buildChild,
  ) {
    return DetectedItemCardView(
      key: NodeKey(node.instanceId),
      category: props.string('category') ?? 'car',
      confidence: props.number('confidence') ?? 0,
      imageUrl: props.string('imageUrl'),
      summary: props.string('summary'),
      isEv: props.boolean('isEv') ?? false,
      fields: props
          .list('fields')
          .map((Object? raw) => detectedFieldFromProp(raw, node))
          .toList(growable: false),
      localPhotos: localPhotos,
    );
  });
}

final ComponentImplementation detectedItemCardComponent =
    buildDetectedItemCardComponent();

class DetectedItemCardView extends StatelessWidget {
  const DetectedItemCardView({
    super.key,
    required this.category,
    required this.confidence,
    required this.fields,
    this.imageUrl,
    this.summary,
    this.isEv = false,
    this.localPhotos,
  });

  final String category;
  final double confidence;
  final String? imageUrl;
  final String? summary;
  final bool isEv;
  final List<DetectedField> fields;
  final Map<String, Uint8List>? localPhotos;

  IconData _categoryIcon() => switch (category.toLowerCase()) {
    'car' => Icons.directions_car_filled,
    'motorcycle' => Icons.two_wheeler,
    'phone' => Icons.smartphone,
    _ => Icons.inventory_2_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    final int confidencePercent = (confidence.clamp(0.0, 1.0) * 100).round();
    final String? summaryText = summary;

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
              _DetectedPhotoHeader(
                imageUrl: imageUrl,
                localPhotos: localPhotos,
                categoryIcon: _categoryIcon(),
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
                  if (isEv)
                    Chip(
                      avatar: const Icon(Icons.electric_bolt, size: 16),
                      label: Text(
                        'EV',
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      backgroundColor: colorScheme.tertiaryContainer,
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
              const SizedBox(height: 8),
              if (summaryText != null && summaryText.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    summaryText,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              for (final DetectedField field in fields)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _DetectedFieldInput(
                    key: ValueKey<String>('field_${field.key}'),
                    field: field,
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
    final Map<String, Uint8List>? photos = localPhotos;
    final Uint8List? bytes = photos == null
        ? null
        : (photos[imageUrl] ?? photos['initial']);

    final Widget placeholder = Container(
      height: 96,
      width: double.infinity,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      alignment: Alignment.center,
      child: Icon(categoryIcon, size: 40, color: colorScheme.primary),
    );
    if (bytes == null) return placeholder;
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.memory(
        bytes,
        height: 140,
        width: double.infinity,
        fit: BoxFit.cover,
        errorBuilder: (BuildContext context, Object error, StackTrace? _) =>
            placeholder,
      ),
    );
  }
}

class _DetectedFieldInput extends StatefulWidget {
  const _DetectedFieldInput({super.key, required this.field});

  final DetectedField field;

  @override
  State<_DetectedFieldInput> createState() => _DetectedFieldInputState();
}

class _DetectedFieldInputState extends State<_DetectedFieldInput> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.field.value,
  );

  @override
  void didUpdateWidget(covariant _DetectedFieldInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    syncController(_controller, widget.field.value);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final DetectedField field = widget.field;
    return TextField(
      controller: _controller,
      enabled: field.editable,
      decoration: InputDecoration(labelText: field.label, isDense: true),
      onChanged: field.onChanged,
    );
  }
}

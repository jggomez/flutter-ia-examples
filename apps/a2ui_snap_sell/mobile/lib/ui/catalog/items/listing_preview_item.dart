import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:genui/genui.dart';
import 'package:json_schema_builder/json_schema_builder.dart';

import 'data_context_binding_ext.dart';
import 'price_range_item.dart';

final Schema _specItemSchema = S.object(
  properties: <String, Schema>{
    'label': S.string(),
    'value': A2uiSchemas.stringReference(),
  },
  required: <String>['label', 'value'],
);

final Schema _checklistItemSchema = S.object(
  properties: <String, Schema>{
    'item': S.string(),
    'label': S.string(),
    'completed': S.boolean(),
    'done': S.boolean(),
  },
  required: <String>['item', 'completed'],
);

final Schema _schema = S.object(
  description: 'Final marketplace listing preview card with specs, completeness checklist, and publish action.',
  properties: <String, Schema>{
    'title': A2uiSchemas.stringReference(),
    'description': A2uiSchemas.stringReference(),
    'category': S.string(enumValues: <String>['car', 'motorcycle', 'phone']),
    'categoryBadge': S.string(),
    'price': A2uiSchemas.numberReference(),
    'priceDisplay': A2uiSchemas.stringReference(),
    'currency': S.string(),
    'imageUrls': S.list(items: S.string()),
    'specs': S.list(items: _specItemSchema),
    'missingChecklist': S.list(items: _checklistItemSchema),
    'checklist': S.list(items: _checklistItemSchema),
    'canPublish': A2uiSchemas.booleanReference(),
    'publishAction': A2uiSchemas.action(),
    'editAction': A2uiSchemas.action(),
  },
  required: <String>[
    'title',
    'description',
    'category',
    'price',
    'currency',
    'imageUrls',
    'specs',
    'missingChecklist',
    'publishAction',
  ],
);

/// The `ListingPreview` custom A2UI catalog item.
final CatalogItem listingPreviewItem = CatalogItem(
  name: 'ListingPreview',
  dataSchema: _schema,
  widgetBuilder: (CatalogItemContext itemContext) {
    final JsonMap json = itemContext.data as JsonMap;
    final String category =
        (json['category'] as String?) ??
        (json['categoryBadge'] as String?) ??
        'car';
    final String currency = (json['currency'] as String?) ?? 'USD';

    final ValueListenable<String?> titleNotifier = itemContext.dataContext
        .subscribeToString(json['title']);
    final ValueListenable<String?> descriptionNotifier = itemContext.dataContext
        .subscribeToString(json['description']);
    final ValueListenable<String?> priceDisplayNotifier = itemContext
        .dataContext
        .subscribeToString(json['priceDisplay']);
    final ValueListenable<bool?> canPublishNotifier = itemContext.dataContext
        .subscribeToBool(json['canPublish']);

    final Object? rawPrice = json['price'];
    ValueListenable<num?>? priceNotifier;
    num? literalPrice;
    if (rawPrice is num) {
      literalPrice = rawPrice;
    } else if (rawPrice is Map && rawPrice['path'] is String) {
      priceNotifier = itemContext.dataContext.subscribeToValue<num>(
        DataPath(rawPrice['path'] as String),
      );
    }

    final List<Object?> rawSpecs =
        (json['specs'] as List<Object?>?) ?? const <Object?>[];
    final List<({String label, ValueListenable<String?> valueNotifier})> specs =
        rawSpecs
            .whereType<Map<Object?, Object?>>()
            .map((Map<Object?, Object?> item) {
              final String label = (item['label'] ?? '').toString();
              final ValueListenable<String?> notifier = itemContext.dataContext
                  .subscribeToString(item['value']);
              return (label: label, valueNotifier: notifier);
            })
            .toList(growable: false);

    final List<Object?> rawChecklist =
        (json['missingChecklist'] as List<Object?>?) ??
        (json['checklist'] as List<Object?>?) ??
        const <Object?>[];
    final List<({String text, bool completed})> checklist = rawChecklist
        .whereType<Map<Object?, Object?>>()
        .map((Map<Object?, Object?> item) {
          final String text = (item['item'] ?? item['label'] ?? '').toString();
          final bool completed =
              (item['completed'] as bool?) ?? (item['done'] as bool?) ?? false;
          return (text: text, completed: completed);
        })
        .toList(growable: false);

    final JsonMap? publishAction = json['publishAction'] as JsonMap?;
    final JsonMap? editAction = json['editAction'] as JsonMap?;

    return _ListingPreviewWidget(
      componentId: itemContext.id,
      surfaceId: itemContext.surfaceId,
      category: category,
      currency: currency,
      titleNotifier: titleNotifier,
      descriptionNotifier: descriptionNotifier,
      priceNotifier: priceNotifier,
      literalPrice: literalPrice,
      priceDisplayNotifier: priceDisplayNotifier,
      canPublishNotifier: canPublishNotifier,
      specs: specs,
      checklist: checklist,
      publishAction: publishAction,
      editAction: editAction,
      dataContext: itemContext.dataContext,
      dispatchEvent: itemContext.dispatchEvent,
    );
  },
);

class _ListingPreviewWidget extends StatefulWidget {
  const _ListingPreviewWidget({
    required this.componentId,
    required this.surfaceId,
    required this.category,
    required this.currency,
    required this.titleNotifier,
    required this.descriptionNotifier,
    required this.priceNotifier,
    required this.literalPrice,
    required this.priceDisplayNotifier,
    required this.canPublishNotifier,
    required this.specs,
    required this.checklist,
    required this.publishAction,
    required this.editAction,
    required this.dataContext,
    required this.dispatchEvent,
  });

  final String componentId;
  final String surfaceId;
  final String category;
  final String currency;
  final ValueListenable<String?> titleNotifier;
  final ValueListenable<String?> descriptionNotifier;
  final ValueListenable<num?>? priceNotifier;
  final num? literalPrice;
  final ValueListenable<String?> priceDisplayNotifier;
  final ValueListenable<bool?> canPublishNotifier;
  final List<({String label, ValueListenable<String?> valueNotifier})> specs;
  final List<({String text, bool completed})> checklist;
  final JsonMap? publishAction;
  final JsonMap? editAction;
  final DataContext dataContext;
  final DispatchEventCallback dispatchEvent;

  @override
  State<_ListingPreviewWidget> createState() => _ListingPreviewWidgetState();
}

class _ListingPreviewWidgetState extends State<_ListingPreviewWidget> {
  bool _isPublishing = false;

  Future<void> _triggerAction(JsonMap? actionDef) async {
    if (actionDef == null) return;
    final JsonMap? eventMap = actionDef['event'] as JsonMap?;
    if (eventMap == null) return;
    final String actionName = (eventMap['name'] as String?) ?? 'action';
    final JsonMap? rawContext = eventMap['context'] as JsonMap?;
    final JsonMap resolved = await resolveContext(
      widget.dataContext,
      rawContext,
    );
    widget.dispatchEvent(
      UserActionEvent(
        name: actionName,
        sourceComponentId: widget.componentId,
        surfaceId: widget.surfaceId,
        context: resolved,
      ),
    );
  }

  Future<void> _handlePublish() async {
    if (_isPublishing) return;
    setState(() {
      _isPublishing = true;
    });

    try {
      await _triggerAction(widget.publishAction);
    } catch (_) {
      if (mounted) {
        setState(() {
          _isPublishing = false;
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
      label: 'Marketplace listing preview',
      child: Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  Chip(
                    label: Text(
                      widget.category.toUpperCase(),
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                  _buildPriceLabel(theme, colorScheme),
                ],
              ),
              const SizedBox(height: 8),
              ValueListenableBuilder<String?>(
                valueListenable: widget.titleNotifier,
                builder: (BuildContext context, String? title, Widget? _) {
                  return Text(
                    title ?? 'Listing Preview',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  );
                },
              ),
              const SizedBox(height: 8),
              ValueListenableBuilder<String?>(
                valueListenable: widget.descriptionNotifier,
                builder:
                    (BuildContext context, String? description, Widget? _) {
                      if (description == null || description.isEmpty) {
                        return const SizedBox.shrink();
                      }
                      return Text(
                        description,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      );
                    },
              ),
              if (widget.specs.isNotEmpty) ...<Widget>[
                const SizedBox(height: 16),
                Text(
                  'Specifications',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: widget.specs
                      .map((
                        ({String label, ValueListenable<String?> valueNotifier})
                        spec,
                      ) {
                        return ValueListenableBuilder<String?>(
                          valueListenable: spec.valueNotifier,
                          builder:
                              (BuildContext context, String? val, Widget? _) {
                                return Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: colorScheme.surfaceContainerHighest,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: <Widget>[
                                      Text(
                                        spec.label,
                                        style: theme.textTheme.labelSmall
                                            ?.copyWith(
                                              color:
                                                  colorScheme.onSurfaceVariant,
                                            ),
                                      ),
                                      Text(
                                        val ?? '-',
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                              fontWeight: FontWeight.w700,
                                            ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                        );
                      })
                      .toList(growable: false),
                ),
              ],
              if (widget.checklist.isNotEmpty) ...<Widget>[
                const SizedBox(height: 16),
                Text(
                  'Listing Readiness Checklist',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                for (final ({String text, bool completed}) item
                    in widget.checklist)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: <Widget>[
                        Icon(
                          item.completed
                              ? Icons.check_circle
                              : Icons.radio_button_unchecked,
                          size: 18,
                          color: item.completed
                              ? colorScheme.primary
                              : colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            item.text,
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
              const SizedBox(height: 16),
              ValueListenableBuilder<bool?>(
                valueListenable: widget.canPublishNotifier,
                builder: (BuildContext context, bool? canPublish, Widget? _) {
                  final bool enabled = (canPublish ?? true) && !_isPublishing;
                  return Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    children: <Widget>[
                      FilledButton.icon(
                        onPressed: enabled ? _handlePublish : null,
                        icon: _isPublishing
                            ? SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: colorScheme.onPrimary,
                                ),
                              )
                            : const Icon(Icons.publish, size: 18),
                        label: const Text('Publish Listing'),
                      ),
                      if (widget.editAction != null)
                        OutlinedButton.icon(
                          onPressed: () => _triggerAction(widget.editAction),
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          label: const Text('Edit Details'),
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPriceLabel(ThemeData theme, ColorScheme colorScheme) {
    if (widget.priceNotifier != null) {
      return ValueListenableBuilder<num?>(
        valueListenable: widget.priceNotifier!,
        builder: (BuildContext context, num? val, Widget? _) {
          final num displayNum = val ?? widget.literalPrice ?? 0;
          return Text(
            '${widget.currency} ${formatPriceNumber(displayNum)}',
            style: theme.textTheme.titleLarge?.copyWith(
              color: colorScheme.primary,
              fontWeight: FontWeight.w800,
            ),
          );
        },
      );
    }
    return ValueListenableBuilder<String?>(
      valueListenable: widget.priceDisplayNotifier,
      builder: (BuildContext context, String? customDisplay, Widget? _) {
        final String text = (customDisplay != null && customDisplay.isNotEmpty)
            ? customDisplay
            : '${widget.currency} ${formatPriceNumber(widget.literalPrice ?? 0)}';
        return Text(
          text,
          style: theme.textTheme.titleLarge?.copyWith(
            color: colorScheme.primary,
            fontWeight: FontWeight.w800,
          ),
        );
      },
    );
  }
}

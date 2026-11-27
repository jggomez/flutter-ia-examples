import 'package:a2ui_core/a2ui_core.dart';
import 'package:a2ui_flutter/a2ui_flutter.dart';
import 'package:flutter/material.dart';

import '../snap_sell_catalog.dart';
import 'price_range_item.dart';

typedef ListingSpec = ({String label, String value});
typedef ChecklistEntry = ({String text, bool completed});

/// `ListingPreview`: final marketplace card with specs, checklist and publish.
final ComponentImplementation listingPreviewComponent =
    implementContractComponent('ListingPreview', _build);

Widget _build(
  BuildContext context,
  ComponentNode<ComponentImplementation> node,
  ComponentProps props,
  ChildWidgetBuilder buildChild,
) {
  return ListingPreviewCard(
    key: NodeKey(node.instanceId),
    title: props.string('title'),
    description: props.string('description'),
    category: props.string('category') ?? 'car',
    currency: props.string('currency') ?? 'USD',
    price: props.number('price') ?? 0,
    specs: props
        .list('specs')
        .whereType<Map<Object?, Object?>>()
        .map(
          (Map<Object?, Object?> s) => (
            label: (s['label'] ?? '').toString(),
            value: ComponentProps.asString(s['value']) ?? '-',
          ),
        )
        .toList(growable: false),
    checklist: props
        .list('missingChecklist')
        .whereType<Map<Object?, Object?>>()
        .map(
          (Map<Object?, Object?> c) => (
            text: (c['item'] ?? '').toString(),
            completed: ComponentProps.asBoolean(c['completed']) ?? false,
          ),
        )
        .toList(growable: false),
    onPublish: props.isValid ? props.action('publishAction') : null,
  );
}

class ListingPreviewCard extends StatefulWidget {
  const ListingPreviewCard({
    super.key,
    required this.category,
    required this.currency,
    required this.price,
    required this.specs,
    required this.checklist,
    this.title,
    this.description,
    this.onPublish,
  });

  final String? title;
  final String? description;
  final String category;
  final String currency;
  final double price;
  final List<ListingSpec> specs;
  final List<ChecklistEntry> checklist;
  final NodeAction? onPublish;

  @override
  State<ListingPreviewCard> createState() => _ListingPreviewCardState();
}

class _ListingPreviewCardState extends State<ListingPreviewCard> {
  bool _isPublishing = false;

  Future<void> _handlePublish() async {
    final NodeAction? publish = widget.onPublish;
    if (_isPublishing || publish == null) return;
    setState(() => _isPublishing = true);
    try {
      await publish();
    } catch (_) {
      if (mounted) setState(() => _isPublishing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    final String? description = widget.description;
    final bool enabled = widget.onPublish != null && !_isPublishing;

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
                  Text(
                    '${widget.currency} ${formatPriceNumber(widget.price)}',
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                widget.title ?? 'Listing Preview',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (description != null && description.isNotEmpty) ...<Widget>[
                const SizedBox(height: 8),
                Text(
                  description,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
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
                  children: <Widget>[
                    for (final ListingSpec spec in widget.specs)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Text(
                              spec.label,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                            Text(
                              spec.value,
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
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
                for (final ChecklistEntry item in widget.checklist)
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
            ],
          ),
        ),
      ),
    );
  }
}

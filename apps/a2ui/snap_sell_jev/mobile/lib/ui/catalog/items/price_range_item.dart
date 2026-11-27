import 'dart:async';

import 'package:a2ui_core/a2ui_core.dart';
import 'package:a2ui_flutter/a2ui_flutter.dart';
import 'package:flutter/material.dart';

import '../snap_sell_catalog.dart';

/// Formats [value] rounded with thousands separators (`23400` -> `23,400`).
String formatPriceNumber(num value) {
  final int rounded = value.round();
  final String digits = rounded.abs().toString();
  final StringBuffer buffer = StringBuffer();
  for (int i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return rounded < 0 ? '-$buffer' : buffer.toString();
}

/// `PriceRange`: market band, two-way bound asking price and live feedback.
///
/// `feedback` is usually `@call priceFeedback(...)`. The renderer catalog
/// does not implement that function, so `a2ui_core` asks the agent with a
/// `callAgentFunction` each time the bound asking price changes, and the
/// agent answers deterministically without an LLM turn.
final ComponentImplementation priceRangeComponent = implementContractComponent(
  'PriceRange',
  _build,
);

Widget _build(
  BuildContext context,
  ComponentNode<ComponentImplementation> node,
  ComponentProps props,
  ChildWidgetBuilder buildChild,
) {
  final double minPrice = props.number('minPrice') ?? 0;
  final double suggested = props.number('suggestedPrice') ?? minPrice;
  final WritableBinding<Object?>? selected = props.writable('selectedPrice');
  return PriceRangeCard(
    key: NodeKey(node.instanceId),
    minPrice: minPrice,
    suggestedPrice: suggested,
    maxPrice: props.number('maxPrice') ?? suggested,
    currency: props.string('currency') ?? 'USD',
    selectedPrice: props.number('selectedPrice') ?? suggested,
    rationale: props.string('rationale'),
    feedback: props.string('feedback'),
    onPriceCommitted: selected == null ? null : (num v) => selected.set(v),
  );
}

class PriceRangeCard extends StatefulWidget {
  const PriceRangeCard({
    super.key,
    required this.minPrice,
    required this.suggestedPrice,
    required this.maxPrice,
    required this.currency,
    required this.selectedPrice,
    this.rationale,
    this.feedback,
    this.onPriceCommitted,
  });

  final double minPrice;
  final double suggestedPrice;
  final double maxPrice;
  final String currency;

  /// Asking price held by the data model.
  final double selectedPrice;
  final String? rationale;

  /// Live verdict computed by the agent function `priceFeedback`.
  final String? feedback;

  /// Writes the asking price back to the data model. Called when a drag ends
  /// or typing pauses, so the agent function is not called on every frame.
  final ValueChanged<num>? onPriceCommitted;

  @override
  State<PriceRangeCard> createState() => _PriceRangeCardState();
}

class _PriceRangeCardState extends State<PriceRangeCard> {
  static const Duration _typingDebounce = Duration(milliseconds: 450);

  late final TextEditingController _textController;
  late double _draft;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _draft = widget.selectedPrice;
    _textController = TextEditingController(text: _draft.round().toString());
  }

  @override
  void didUpdateWidget(covariant PriceRangeCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedPrice != widget.selectedPrice &&
        widget.selectedPrice != _draft) {
      _draft = widget.selectedPrice;
      syncController(_textController, _draft.round().toString());
    }
  }

  void _commit(num value) {
    _debounce?.cancel();
    if (value != widget.selectedPrice) widget.onPriceCommitted?.call(value);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    final double safeMin = widget.minPrice;
    final double safeMax = widget.maxPrice > safeMin
        ? widget.maxPrice
        : safeMin + 100.0;
    final String currency = widget.currency;
    final String? feedback = widget.feedback;
    final String? rationale = widget.rationale;

    return Semantics(
      container: true,
      label:
          'Price range $currency ${formatPriceNumber(widget.minPrice)} to '
          '${formatPriceNumber(widget.maxPrice)}',
      child: Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              SizedBox(
                width: double.infinity,
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 6,
                  children: <Widget>[
                    Text(
                      'Suggested Price Range',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        'Suggested: $currency '
                        '${formatPriceNumber(widget.suggestedPrice)}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 6,
                  children: <Widget>[
                    Text(
                      'Min: $currency ${formatPriceNumber(widget.minPrice)}',
                      style: theme.textTheme.bodySmall,
                    ),
                    Text(
                      '$currency ${formatPriceNumber(_draft)}',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: colorScheme.primary,
                      ),
                    ),
                    Text(
                      'Max: $currency ${formatPriceNumber(widget.maxPrice)}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              Slider(
                value: _draft.clamp(safeMin, safeMax),
                min: safeMin,
                max: safeMax,
                onChanged: (double value) {
                  setState(() => _draft = value.roundToDouble());
                  syncController(_textController, _draft.round().toString());
                },
                onChangeEnd: (double value) => _commit(value.round()),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _textController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Asking Price ($currency)',
                  prefixText: '$currency ',
                  isDense: true,
                ),
                onChanged: (String text) {
                  final num? parsed = num.tryParse(
                    text.replaceAll(',', '').trim(),
                  );
                  if (parsed == null) return;
                  setState(() => _draft = parsed.toDouble());
                  _debounce?.cancel();
                  _debounce = Timer(_typingDebounce, () => _commit(parsed));
                },
                onSubmitted: (String text) {
                  final num? parsed = num.tryParse(
                    text.replaceAll(',', '').trim(),
                  );
                  if (parsed != null) _commit(parsed);
                },
              ),
              if (feedback != null && feedback.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Row(
                    key: const Key('price_feedback'),
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Icon(
                        Icons.insights,
                        size: 18,
                        color: colorScheme.primary,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          feedback,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              if (rationale != null && rationale.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    rationale,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

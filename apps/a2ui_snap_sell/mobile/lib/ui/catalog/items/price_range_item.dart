import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:genui/genui.dart';
import 'package:json_schema_builder/json_schema_builder.dart';

import 'data_context_binding_ext.dart';

final Schema _schema = S.object(
  description: 'Visualizes market price band with suggested price and two-way bound asking price.',
  properties: <String, Schema>{
    'minPrice': S.number(minimum: 0),
    'suggestedPrice': S.number(minimum: 0),
    'maxPrice': S.number(minimum: 0),
    'selectedPrice': A2uiSchemas.numberReference(),
    'selectedPricePath': S.string(),
    'currency': S.string(),
    'rationale': A2uiSchemas.stringReference(),
  },
  required: <String>[
    'minPrice',
    'suggestedPrice',
    'maxPrice',
    'selectedPrice',
    'currency',
    'rationale',
  ],
);

/// Format a number with comma thousands separators.
String formatPriceNumber(num value) {
  final int rounded = value.round();
  final String digits = rounded.abs().toString();
  final StringBuffer buffer = StringBuffer();
  for (int i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) {
      buffer.write(',');
    }
    buffer.write(digits[i]);
  }
  return rounded < 0 ? '-$buffer' : buffer.toString();
}

/// The `PriceRange` custom A2UI catalog item.
final CatalogItem priceRangeItem = CatalogItem(
  name: 'PriceRange',
  dataSchema: _schema,
  widgetBuilder: (CatalogItemContext itemContext) {
    final JsonMap json = itemContext.data as JsonMap;
    final double minPrice = (json['minPrice'] as num?)?.toDouble() ?? 0.0;
    final double suggestedPrice =
        (json['suggestedPrice'] as num?)?.toDouble() ?? minPrice;
    final double maxPrice =
        (json['maxPrice'] as num?)?.toDouble() ?? suggestedPrice;
    final String currency = (json['currency'] as String?) ?? 'USD';

    final Object? selectedPriceRaw = json['selectedPrice'];
    String? boundPath = json['selectedPricePath'] as String?;
    if (boundPath == null &&
        selectedPriceRaw is Map &&
        selectedPriceRaw['path'] is String) {
      boundPath = selectedPriceRaw['path'] as String;
    }

    final ValueListenable<num?> selectedPriceNotifier = itemContext.dataContext
        .subscribeToValue<num>(DataPath(boundPath ?? '/pricing/askingPrice'));
    final ValueListenable<String?> rationaleNotifier = itemContext.dataContext
        .subscribeToString(json['rationale']);

    final num? literalSelectedPrice = selectedPriceRaw is num
        ? selectedPriceRaw
        : null;

    return _PriceRangeWidget(
      minPrice: minPrice,
      suggestedPrice: suggestedPrice,
      maxPrice: maxPrice,
      currency: currency,
      boundPath: boundPath,
      literalSelectedPrice: literalSelectedPrice,
      selectedPriceNotifier: selectedPriceNotifier,
      rationaleNotifier: rationaleNotifier,
      dataContext: itemContext.dataContext,
    );
  },
);

class _PriceRangeWidget extends StatefulWidget {
  const _PriceRangeWidget({
    required this.minPrice,
    required this.suggestedPrice,
    required this.maxPrice,
    required this.currency,
    required this.boundPath,
    required this.literalSelectedPrice,
    required this.selectedPriceNotifier,
    required this.rationaleNotifier,
    required this.dataContext,
  });

  final double minPrice;
  final double suggestedPrice;
  final double maxPrice;
  final String currency;
  final String? boundPath;
  final num? literalSelectedPrice;
  final ValueListenable<num?> selectedPriceNotifier;
  final ValueListenable<String?> rationaleNotifier;
  final DataContext dataContext;

  @override
  State<_PriceRangeWidget> createState() => _PriceRangeWidgetState();
}

class _PriceRangeWidgetState extends State<_PriceRangeWidget> {
  late final TextEditingController _textController;

  double get _effectivePrice {
    final num? fromModel = widget.selectedPriceNotifier.value;
    if (fromModel != null) {
      return fromModel.toDouble();
    }
    if (widget.literalSelectedPrice != null) {
      return widget.literalSelectedPrice!.toDouble();
    }
    return widget.suggestedPrice;
  }

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(
      text: _effectivePrice.round().toString(),
    );
    widget.selectedPriceNotifier.addListener(_onModelPriceChanged);
  }

  @override
  void didUpdateWidget(covariant _PriceRangeWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedPriceNotifier != widget.selectedPriceNotifier) {
      oldWidget.selectedPriceNotifier.removeListener(_onModelPriceChanged);
      widget.selectedPriceNotifier.addListener(_onModelPriceChanged);
      _onModelPriceChanged();
    }
  }

  void _onModelPriceChanged() {
    final String formatted = _effectivePrice.round().toString();
    final String strippedCurrent = _textController.text.replaceAll(',', '');
    if (strippedCurrent != formatted) {
      _textController.value = _textController.value.copyWith(
        text: formatted,
        selection: TextSelection.collapsed(offset: formatted.length),
      );
    }
    if (mounted) {
      setState(() {});
    }
  }

  void _updatePrice(num newPrice) {
    final String? path = widget.boundPath;
    if (path != null && path.isNotEmpty) {
      widget.dataContext.update(DataPath(path), newPrice);
    }
  }

  @override
  void dispose() {
    widget.selectedPriceNotifier.removeListener(_onModelPriceChanged);
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
    final double sliderValue = _effectivePrice.clamp(safeMin, safeMax);

    return Semantics(
      container: true,
      label:
          'Price range ${widget.currency} ${formatPriceNumber(widget.minPrice)} to ${formatPriceNumber(widget.maxPrice)}',
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
                        'Suggested: ${widget.currency} ${formatPriceNumber(widget.suggestedPrice)}',
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
                      'Min: ${widget.currency} ${formatPriceNumber(widget.minPrice)}',
                      style: theme.textTheme.bodySmall,
                    ),
                    Text(
                      '${widget.currency} ${formatPriceNumber(_effectivePrice)}',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: colorScheme.primary,
                      ),
                    ),
                    Text(
                      'Max: ${widget.currency} ${formatPriceNumber(widget.maxPrice)}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              Slider(
                value: sliderValue,
                min: safeMin,
                max: safeMax,
                onChanged: (double value) {
                  final int rounded = value.round();
                  _textController.text = rounded.toString();
                  _updatePrice(rounded);
                },
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _textController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Asking Price (${widget.currency})',
                  prefixText: '${widget.currency} ',
                  isDense: true,
                ),
                onChanged: (String text) {
                  final String cleaned = text.replaceAll(',', '').trim();
                  final num? parsed = num.tryParse(cleaned);
                  if (parsed != null) {
                    _updatePrice(parsed);
                  }
                },
              ),
              ValueListenableBuilder<String?>(
                valueListenable: widget.rationaleNotifier,
                builder: (BuildContext context, String? rationale, Widget? _) {
                  if (rationale == null || rationale.isEmpty) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      rationale,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Alias matching component widget naming (`PriceRangeCard`).
typedef PriceRangeCard = _PriceRangeWidget;

import 'package:a2ui_core/a2ui_core.dart';
import 'package:a2ui_flutter/a2ui_flutter.dart';
import 'package:flutter/material.dart';

import '../snap_sell_catalog.dart';

/// Snap & Sell override of the Basic Catalog `Button`.
///
/// Same contract as the basic one (`child`, `action`, `variant`, `@checks`);
/// adds Snap & Sell styling and a spinner while the action is in flight.
final ComponentImplementation snapSellButtonComponent =
    implementContractComponent('Button', _build);

Widget _build(
  BuildContext context,
  ComponentNode<ComponentImplementation> node,
  ComponentProps props,
  ChildWidgetBuilder buildChild,
) {
  final ComponentNode<ComponentImplementation>? child = props.child('child');
  return SnapSellButton(
    key: NodeKey(node.instanceId),
    variant: props.string('variant'),
    // `@checks` failing (for example a required field left empty) disables
    // the button; the first failure message becomes its tooltip.
    disabledReason: props.isValid ? null : props.validationErrors.firstOrNull,
    isValid: props.isValid,
    onPressed: props.action('action'),
    label: child == null ? const SizedBox.shrink() : buildChild(child),
  );
}

class SnapSellButton extends StatefulWidget {
  const SnapSellButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant,
    this.isValid = true,
    this.disabledReason,
  });

  final Widget label;
  final NodeAction? onPressed;
  final String? variant;
  final bool isValid;
  final String? disabledReason;

  @override
  State<SnapSellButton> createState() => _SnapSellButtonState();
}

class _SnapSellButtonState extends State<SnapSellButton> {
  bool _isLoading = false;

  Future<void> _handlePress() async {
    final NodeAction? action = widget.onPressed;
    if (_isLoading || action == null) return;
    setState(() => _isLoading = true);
    try {
      await action();
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    final String variant = widget.variant ?? '';
    final bool primary = variant == 'primary';

    final Widget content = _isLoading
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: primary ? colorScheme.onPrimary : colorScheme.primary,
                ),
              ),
              const SizedBox(width: 8),
              widget.label,
            ],
          )
        : widget.label;

    final bool enabled =
        widget.isValid && !_isLoading && widget.onPressed != null;
    final VoidCallback? onPressed = enabled ? _handlePress : null;

    final Widget button = switch (variant) {
      'borderless' => TextButton(
        style: TextButton.styleFrom(
          foregroundColor: colorScheme.onSurface,
          disabledForegroundColor: colorScheme.primary,
        ),
        onPressed: onPressed,
        child: content,
      ),
      _ => ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary ? colorScheme.primary : colorScheme.surface,
          foregroundColor: primary
              ? colorScheme.onPrimary
              : colorScheme.onSurface,
          disabledBackgroundColor: primary
              ? colorScheme.primary.withValues(alpha: 0.7)
              : null,
          disabledForegroundColor: primary ? colorScheme.onPrimary : null,
          textStyle: theme.textTheme.bodyLarge,
        ),
        onPressed: onPressed,
        child: content,
      ),
    };
    final String? reason = widget.disabledReason;
    return reason == null ? button : Tooltip(message: reason, child: button);
  }
}

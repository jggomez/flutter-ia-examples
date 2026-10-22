import 'dart:async';

import 'package:flutter/material.dart';
import 'package:genui/genui.dart';
import 'package:json_schema_builder/json_schema_builder.dart';

final Schema _schema = S.object(
  description: 'An interactive button that triggers an action when pressed.',
  properties: <String, Schema>{
    'child': A2uiSchemas.componentReference(
      description:
          'The ID of a child widget. This should always be set, e.g. to the ID '
          'of a `Text` widget.',
    ),
    'action': A2uiSchemas.action(),
    'variant': S.string(
      description: 'A hint for the button style.',
      enumValues: <String>['default', 'primary', 'borderless'],
    ),
    'checks': A2uiSchemas.checkable(),
  },
  required: <String>['child', 'action'],
);

/// Custom A2UI `Button` catalog item overriding the basic button with an inline
/// loading spinner and double-tap prevention.
final CatalogItem snapSellButtonItem = CatalogItem(
  name: 'Button',
  dataSchema: _schema,
  widgetBuilder: (CatalogItemContext itemContext) {
    final JsonMap json = itemContext.data as JsonMap;
    final Object? rawChild = json['child'];
    final String childId = rawChild is String ? rawChild : '';
    final JsonMap action =
        (json['action'] as JsonMap?) ?? const <String, Object?>{};
    final String? variant = json['variant'] as String?;
    final List<JsonMap>? checks = (json['checks'] as List<Object?>?)
        ?.cast<JsonMap>();

    return _SnapSellButtonWidget(
      itemContext: itemContext,
      childId: childId,
      action: action,
      variant: variant,
      checks: checks,
    );
  },
);

class _SnapSellButtonWidget extends StatefulWidget {
  const _SnapSellButtonWidget({
    required this.itemContext,
    required this.childId,
    required this.action,
    required this.variant,
    required this.checks,
  });

  final CatalogItemContext itemContext;
  final String childId;
  final JsonMap action;
  final String? variant;
  final List<JsonMap>? checks;

  @override
  State<_SnapSellButtonWidget> createState() => _SnapSellButtonWidgetState();
}

class _SnapSellButtonWidgetState extends State<_SnapSellButtonWidget> {
  bool _isLoading = false;

  Future<void> _handlePress() async {
    if (_isLoading) return;
    setState(() {
      _isLoading = true;
    });

    try {
      final JsonMap actionData = widget.action;
      if (actionData.containsKey('event')) {
        final JsonMap? eventMap = actionData['event'] as JsonMap?;
        if (eventMap != null) {
          final String actionName = (eventMap['name'] as String?) ?? 'action';
          final JsonMap? contextDefinition = eventMap['context'] as JsonMap?;

          final JsonMap resolvedContext = await resolveContext(
            widget.itemContext.dataContext,
            contextDefinition,
          );

          widget.itemContext.dispatchEvent(
            UserActionEvent(
              name: actionName,
              sourceComponentId: widget.itemContext.id,
              surfaceId: widget.itemContext.surfaceId,
              context: resolvedContext,
            ),
          );
        }
      } else if (actionData.containsKey('functionCall')) {
        final JsonMap? funcMap = actionData['functionCall'] as JsonMap?;
        if (funcMap != null) {
          final String callName = (funcMap['call'] as String?) ?? '';
          if (callName == 'closeModal') {
            if (mounted && widget.itemContext.buildContext.mounted) {
              Navigator.of(context).pop();
            }
            return;
          }

          final Stream<Object?> resultStream = widget.itemContext.dataContext
              .resolve(funcMap);
          final StreamIterator<Object?> iterator = StreamIterator<Object?>(
            resultStream,
          );
          try {
            await iterator.moveNext().timeout(
              const Duration(seconds: 10),
              onTimeout: () => throw TimeoutException(
                'Function execution for $callName timed out',
              ),
            );
          } catch (exception, stackTrace) {
            if (exception is A2uiFunctionException) {
              widget.itemContext.reportError(exception, stackTrace);
            } else if (exception is TimeoutException) {
              widget.itemContext.reportError(
                A2uiFunctionException(
                  'Function execution timed out.',
                  functionName: callName,
                  cause: exception,
                ),
                stackTrace,
              );
            } else {
              widget.itemContext.reportError(
                A2uiFunctionException(
                  'Function execution failed. Please check arguments and try again.',
                  functionName: callName,
                  cause: exception,
                ),
                stackTrace,
              );
            }
          } finally {
            await iterator.cancel();
          }
        }
      }
    } catch (e, stack) {
      widget.itemContext.reportError(e, stack);
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    final String variant = widget.variant ?? '';
    final bool primary = variant == 'primary';
    final bool borderless = variant == 'borderless';

    final TextStyle? textStyle = theme.textTheme.bodyLarge?.copyWith(
      color: primary ? colorScheme.onPrimary : colorScheme.onSurface,
    );

    final ButtonStyle style = switch (variant) {
      'primary' => ElevatedButton.styleFrom(
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        disabledBackgroundColor: colorScheme.primary.withValues(alpha: 0.7),
        disabledForegroundColor: colorScheme.onPrimary,
      ),
      'borderless' => TextButton.styleFrom(
        foregroundColor: colorScheme.onSurface,
        disabledForegroundColor: colorScheme.primary,
      ),
      _ => ElevatedButton.styleFrom(
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
      ),
    };

    final Color spinnerColor = primary
        ? colorScheme.onPrimary
        : colorScheme.primary;

    final Widget child = widget.itemContext.buildChild(widget.childId);
    final Widget content = _isLoading
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: spinnerColor,
                ),
              ),
              const SizedBox(width: 8),
              child,
            ],
          )
        : child;

    return StreamBuilder<String?>(
      stream: ValidationHelper.validateStream(
        widget.checks,
        widget.itemContext.dataContext,
      ),
      builder: (BuildContext context, AsyncSnapshot<String?> snapshot) {
        final bool isValid = snapshot.data == null;
        final bool enabled = isValid && !_isLoading;
        final VoidCallback? onPressed = enabled ? _handlePress : null;

        if (borderless) {
          return TextButton(style: style, onPressed: onPressed, child: content);
        }

        return ElevatedButton(
          style: style.copyWith(
            textStyle: WidgetStatePropertyAll<TextStyle?>(textStyle),
          ),
          onPressed: onPressed,
          child: content,
        );
      },
    );
  }
}

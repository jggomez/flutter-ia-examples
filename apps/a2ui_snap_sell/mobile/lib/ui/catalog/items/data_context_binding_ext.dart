import 'package:flutter/foundation.dart';
import 'package:genui/genui.dart';

/// Convenience binding helpers on [DataContext] for A2UI v0.9 dynamic properties
/// (`DynamicString`, `DynamicBoolean`, `DynamicNumber`, or `DataPath`).
extension DataContextBindingExtension on DataContext {
  /// Subscribes to a `DynamicString` (either `{"path": "/..."}` or a literal string).
  ValueListenable<String?> subscribeToString(Object? raw) {
    if (raw is Map && raw['path'] is String) {
      return subscribe<String>(DataPath(raw['path'] as String));
    }
    if (raw is String) {
      return ValueNotifier<String?>(raw);
    }
    return ValueNotifier<String?>(raw?.toString());
  }

  /// Subscribes to a `DynamicBoolean` (either `{"path": "/..."}` or a literal bool).
  ValueListenable<bool?> subscribeToBool(Object? raw) {
    if (raw is Map && raw['path'] is String) {
      return subscribe<bool>(DataPath(raw['path'] as String));
    }
    if (raw is bool) {
      return ValueNotifier<bool?>(raw);
    }
    return ValueNotifier<bool?>(null);
  }

  /// Subscribes to a typed value at [path] in the [DataModel].
  ValueListenable<T?> subscribeToValue<T>(DataPath path) {
    return subscribe<T>(path);
  }
}

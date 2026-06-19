import 'data_model.dart';

/// Resolves A2UI data bindings within a props map.
///
/// A prop value shaped `{"path": "/x/y"}` is replaced by the model value at
/// that path. Literal values pass through unchanged. With [scope], relative
/// paths (no leading `/`) resolve under `scope` — used for `List` item
/// templates where each item's binding root is `/dataPath/<index>`.
class Binding {
  const Binding._();

  static Map<String, dynamic> resolveProps(
    Map<String, dynamic> props,
    DataModel model, {
    String? scope,
  }) {
    return {
      for (final entry in props.entries)
        entry.key: _resolveValue(entry.value, model, scope),
    };
  }

  static Object? _resolveValue(Object? value, DataModel model, String? scope) {
    if (value is Map && value.containsKey('path')) {
      final raw = value['path'].toString();
      final path = raw.startsWith('/')
          ? raw
          : '${scope ?? ''}/$raw';
      return model.get(path);
    }
    return value;
  }
}

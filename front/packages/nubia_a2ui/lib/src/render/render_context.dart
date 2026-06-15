import 'package:flutter/widgets.dart';

import '../model/component_def.dart';
import '../model/data_model.dart';
import 'action_dispatcher.dart';

/// Passed to every component builder. Gives access to the surface data model,
/// a way to render a child component by id, and action wiring.
class A2uiRenderContext {
  const A2uiRenderContext({
    required this.surfaceId,
    required this.dataModel,
    required this.dispatcher,
    required this.components,
    required this.buildChild,
    this.scope,
  });

  final String surfaceId;
  final DataModel dataModel;
  final A2uiActionDispatcher dispatcher;

  /// All component definitions in the surface, keyed by id.
  final Map<String, ComponentDef> components;

  /// Renders a child component by id (optionally within an item [scope]).
  final Widget Function(String id, {String? scope}) buildChild;

  /// Binding scope for relative paths (List item templates).
  final String? scope;

  /// Returns a callback that dispatches the action referenced by [ref], or null
  /// when [ref] is absent (so disabled state propagates naturally).
  VoidCallback? action(Object? ref, {Map<String, dynamic> args = const {}}) {
    if (ref == null) return null;
    return () => dispatcher.dispatch(surfaceId, ref, args);
  }

  /// Like [action] but for value-carrying inputs (TextField, Slider…).
  ValueChanged<T>? valueAction<T>(Object? ref, {String argKey = 'value'}) {
    if (ref == null) return null;
    return (value) => dispatcher.dispatch(surfaceId, ref, {argKey: value});
  }
}

/// A single A2UI component instance within a surface.
///
/// Containers reference their children by id (adjacency-list form), so the
/// renderer reconstructs the tree from a flat component list.
class ComponentDef {
  const ComponentDef({
    required this.id,
    required this.component,
    this.props = const {},
    this.children = const [],
  });

  final String id;

  /// Catalog component type, e.g. "Button", "Column".
  final String component;

  /// Raw props (may contain `{"path": "/..."}` bindings or action refs).
  final Map<String, dynamic> props;

  /// Child component ids (for container components).
  final List<String> children;

  factory ComponentDef.fromJson(Map<String, dynamic> json) {
    final reserved = {'id', 'component', 'children'};
    final props = <String, dynamic>{
      for (final e in json.entries)
        if (!reserved.contains(e.key)) e.key: e.value,
    };
    return ComponentDef(
      id: json['id'] as String,
      component: json['component'] as String,
      props: props,
      children: (json['children'] as List? ?? const [])
          .map((e) => e.toString())
          .toList(),
    );
  }
}

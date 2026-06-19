import 'package:flutter/foundation.dart';

/// A surface's mutable JSON data model with JSON-Pointer-style access.
///
/// Paths look like `/patient/name` or `/items/0/title`. The renderer listens
/// for changes so `updateDataModel` messages trigger a rebuild.
class DataModel extends ChangeNotifier {
  DataModel([Map<String, dynamic>? initial])
      : _root = initial ?? <String, dynamic>{};

  Map<String, dynamic> _root;

  Map<String, dynamic> get root => _root;

  static List<String> _segments(String path) =>
      path.split('/').where((s) => s.isNotEmpty).toList();

  /// Resolves [path] against the model root. Returns null if absent.
  Object? get(String path) {
    Object? node = _root;
    for (final seg in _segments(path)) {
      if (node is Map) {
        node = node[seg];
      } else if (node is List) {
        final i = int.tryParse(seg);
        node = (i != null && i >= 0 && i < node.length) ? node[i] : null;
      } else {
        return null;
      }
      if (node == null) return null;
    }
    return node;
  }

  /// Sets [value] at [path], creating intermediate maps as needed.
  void set(String path, Object? value) {
    final segs = _segments(path);
    if (segs.isEmpty) return;
    Map<String, dynamic> node = _root;
    for (var i = 0; i < segs.length - 1; i++) {
      final next = node[segs[i]];
      if (next is Map<String, dynamic>) {
        node = next;
      } else {
        final created = <String, dynamic>{};
        node[segs[i]] = created;
        node = created;
      }
    }
    node[segs.last] = value;
    notifyListeners();
  }

  /// Shallow-merges [patch] into the root.
  void merge(Map<String, dynamic> patch) {
    _root = {..._root, ...patch};
    notifyListeners();
  }
}

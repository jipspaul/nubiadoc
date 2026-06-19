import 'dart:async';

import 'package:flutter/material.dart';

import '../messages/a2ui_message.dart';
import '../model/component_def.dart';
import '../model/data_model.dart';
import '../registry/component_registry.dart';
import '../transport/a2ui_transport.dart';
import 'action_dispatcher.dart';
import 'render_context.dart';

/// Renders A2UI surfaces from a [transport] message stream using a
/// [ComponentRegistry] that maps catalog components to Nubia widgets.
///
/// Drives one or more surfaces; the most-recently created surface is shown.
class A2uiRenderer extends StatefulWidget {
  const A2uiRenderer({
    super.key,
    required this.transport,
    required this.endpoint,
    this.registry,
    this.headers,
    this.onLocalAction,
  });

  final A2uiTransport transport;
  final Uri endpoint;
  final ComponentRegistry? registry;
  final Map<String, String>? headers;

  /// Optional local action handler (return true if handled).
  final bool Function(String surfaceId, String action, Map<String, dynamic> args)?
      onLocalAction;

  @override
  State<A2uiRenderer> createState() => _A2uiRendererState();
}

class _A2uiRendererState extends State<A2uiRenderer> {
  late final ComponentRegistry _registry;
  late final A2uiActionDispatcher _dispatcher;
  StreamSubscription<A2uiMessage>? _sub;

  final Map<String, _Surface> _surfaces = {};
  String? _activeSurfaceId;

  @override
  void initState() {
    super.initState();
    _registry = widget.registry ?? ComponentRegistry.nubiaDefault();
    _dispatcher = A2uiActionDispatcher(
      transport: widget.transport,
      onLocal: widget.onLocalAction,
    );
    _sub = widget.transport
        .connect(widget.endpoint, headers: widget.headers)
        .listen(_apply, onError: (_) {});
  }

  void _apply(A2uiMessage msg) {
    setState(() {
      switch (msg) {
        case CreateSurface(:final surfaceId, :final root):
          _surfaces[surfaceId] = _Surface(root: root);
          _activeSurfaceId = surfaceId;
        case UpdateComponents(:final surfaceId, :final components):
          final s = _surfaces.putIfAbsent(surfaceId, _Surface.new);
          for (final def in components) {
            s.components[def.id] = def;
            s.root ??= def.id;
          }
        case UpdateDataModel(:final surfaceId, :final patch):
          _surfaces.putIfAbsent(surfaceId, _Surface.new).dataModel.merge(patch);
        case DeleteSurface(:final surfaceId):
          _surfaces.remove(surfaceId);
          if (_activeSurfaceId == surfaceId) {
            _activeSurfaceId =
                _surfaces.isEmpty ? null : _surfaces.keys.last;
          }
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    widget.transport.close();
    for (final s in _surfaces.values) {
      s.dataModel.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final id = _activeSurfaceId;
    if (id == null) return const SizedBox.shrink();
    final surface = _surfaces[id]!;
    final rootId = surface.root;
    if (rootId == null) return const SizedBox.shrink();

    return AnimatedBuilder(
      animation: surface.dataModel,
      builder: (context, _) => _buildComponent(context, surface, rootId, null),
    );
  }

  Widget _buildComponent(
    BuildContext context,
    _Surface surface,
    String id, // component id
    String? scope,
  ) {
    final def = surface.components[id];
    if (def == null) return const SizedBox.shrink();
    final ctx = A2uiRenderContext(
      surfaceId: _activeSurfaceId!,
      dataModel: surface.dataModel,
      dispatcher: _dispatcher,
      components: surface.components,
      scope: scope,
      buildChild: (childId, {String? scope}) =>
          _buildComponent(context, surface, childId, scope),
    );
    return _registry.build(
        def.component, context, def.props, def.children, ctx);
  }
}

class _Surface {
  _Surface({this.root});
  String? root;
  final Map<String, ComponentDef> components = {};
  final DataModel dataModel = DataModel();
}

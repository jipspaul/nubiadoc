import 'package:flutter/material.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

import '../model/binding.dart';
import '../render/render_context.dart';

/// Builds a native widget for one resolved component.
typedef ComponentBuilder = Widget Function(
  BuildContext context,
  Map<String, dynamic> props,
  List<String> children,
  A2uiRenderContext ctx,
);

/// Maps A2UI catalog component type strings to Nubia widget builders.
///
/// The default registry covers the `nubia.catalog.v1` catalog 1:1. Apps can
/// [override] or add entries (e.g. a custom `SignatureWedge`).
class ComponentRegistry {
  ComponentRegistry(Map<String, ComponentBuilder> builders)
      : _builders = Map.of(builders);

  final Map<String, ComponentBuilder> _builders;

  Iterable<String> get types => _builders.keys;
  bool contains(String type) => _builders.containsKey(type);

  ComponentRegistry override(Map<String, ComponentBuilder> extra) =>
      ComponentRegistry({..._builders, ...extra});

  Widget build(
    String type,
    BuildContext context,
    Map<String, dynamic> rawProps,
    List<String> children,
    A2uiRenderContext ctx,
  ) {
    final builder = _builders[type];
    if (builder == null) {
      return _unknown(type);
    }
    final props = Binding.resolveProps(rawProps, ctx.dataModel, scope: ctx.scope);
    return builder(context, props, children, ctx);
  }

  static Widget _unknown(String type) => Container(
        padding: const EdgeInsets.all(8),
        color: const Color(0x33FF0000),
        child: Text('Unknown component: $type'),
      );

  /// The default Nubia design-system registry.
  static ComponentRegistry nubiaDefault() => ComponentRegistry({
        'Text': (c, p, _, __) => DsProps.text(p),
        'Icon': (c, p, _, __) =>
            Icon(_icon(p['name'] as String?)),
        'Image': (c, p, _, __) {
          final src = p['src'] as String?;
          return src == null ? const SizedBox.shrink() : Image.network(src);
        },
        'Divider': (c, p, _, __) => const Divider(),
        'Row': (c, p, children, ctx) => Row(
              mainAxisSize: MainAxisSize.min,
              children: _spaced(
                  children.map((id) => ctx.buildChild(id, scope: ctx.scope)),
                  DsProps.number(p, 'gap', 8),
                  Axis.horizontal),
            ),
        'Column': (c, p, children, ctx) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: _spaced(
                  children.map((id) => ctx.buildChild(id, scope: ctx.scope)),
                  DsProps.number(p, 'gap', 8),
                  Axis.vertical),
            ),
        'List': (c, p, _, ctx) {
          final dataPath = p['dataPath'] as String? ?? '';
          final template = p['itemTemplate'] as String?;
          final list = ctx.dataModel.get(dataPath);
          if (template == null || list is! List) return const SizedBox.shrink();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < list.length; i++)
                ctx.buildChild(template, scope: '$dataPath/$i'),
            ],
          );
        },
        'Card': (c, p, children, ctx) => NubiaCard(
              state: DsProps.cardStates[DsProps.str(p, 'state', 'static')] ??
                  NubiaCardState.static_,
              onTap: ctx.action(p['onTap']),
              child: children.isEmpty
                  ? const SizedBox.shrink()
                  : ctx.buildChild(children.first, scope: ctx.scope),
            ),
        'Tabs': (c, p, children, ctx) {
          final tabs = (p['tabs'] as List?)?.map((e) => e.toString()).toList() ??
              const <String>[];
          return NubiaTabs(
            tabs: tabs,
            views: [
              for (final id in children) ctx.buildChild(id, scope: ctx.scope),
            ],
          );
        },
        'Button': (c, p, _, ctx) =>
            DsProps.button(p, onPressed: ctx.action(p['onPressed'])),
        'TextField': (c, p, _, ctx) => DsProps.textField(p,
            onChanged: ctx.valueAction<String>(p['onChanged'])),
        'CheckBox': (c, p, _, ctx) => DsProps.checkbox(p,
            onChanged: ctx.valueAction<bool>(p['onChanged'])),
        'Slider': (c, p, _, ctx) => DsProps.slider(p,
            onChanged: ctx.valueAction<double>(p['onChanged'])),
        'ChoicePicker': (c, p, _, ctx) => DsProps.choicePicker(p,
            onChanged: ctx.valueAction<String>(p['onChanged'])),
        'DateTimeInput': (c, p, _, ctx) => NubiaDateTimeInput(
              label: p['label'] as String?,
              withTime: DsProps.boolean(p, 'withTime'),
              onChanged: ctx.valueAction<DateTime>(p['onChanged']),
            ),
        'Modal': (c, p, children, ctx) => NubiaCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (p['title'] != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(DsProps.str(p, 'title'),
                          style: Theme.of(c).textTheme.titleMedium),
                    ),
                  for (final id in children)
                    ctx.buildChild(id, scope: ctx.scope),
                ],
              ),
            ),
        'Chip': (c, p, _, ctx) => DsProps.chip(p, onTap: ctx.action(p['onTap'])),
        'Badge': (c, p, _, __) => DsProps.badge(p),
        'Avatar': (c, p, _, __) => DsProps.avatar(p),
        'StatusPill': (c, p, _, __) => DsProps.statusPill(p),
      });

  static List<Widget> _spaced(Iterable<Widget> widgets, double gap, Axis axis) {
    final list = widgets.toList();
    final out = <Widget>[];
    for (var i = 0; i < list.length; i++) {
      out.add(list[i]);
      if (i != list.length - 1) {
        out.add(axis == Axis.horizontal
            ? SizedBox(width: gap)
            : SizedBox(height: gap));
      }
    }
    return out;
  }

  static IconData _icon(String? name) {
    switch (name) {
      case 'check':
        return Icons.check;
      case 'calendar':
        return Icons.calendar_today_outlined;
      case 'message':
        return Icons.message_outlined;
      case 'person':
        return Icons.person_outline;
      default:
        return Icons.circle_outlined;
    }
  }
}

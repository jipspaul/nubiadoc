import 'package:flutter/material.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

/// Panneau « Personnaliser » du dashboard (#7161) — remplace l'affichage des
/// widgets par une liste réordonnable (glisser la poignée) où chaque widget
/// du catalogue peut être masqué/affiché (case à cocher). Persistance
/// immédiate déléguée à `DashboardLayoutCubit` via [onReorder]/[onToggle].
class DashboardCustomizePanel extends StatelessWidget {
  const DashboardCustomizePanel({
    super.key,
    required this.order,
    required this.hiddenIds,
    required this.labels,
    required this.onReorder,
    required this.onToggle,
  });

  final List<String> order;
  final Set<String> hiddenIds;
  final Map<String, String> labels;
  final void Function(int oldIndex, int newIndex) onReorder;
  final void Function(String widgetId) onToggle;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return NubiaCard(
      key: const Key('dashboard_customize_panel'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Personnaliser le tableau de bord',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            'Glissez pour réordonner, décochez pour masquer.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 8),
          ReorderableListView.builder(
            key: const Key('dashboard_customize_list'),
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: order.length,
            onReorder: onReorder,
            itemBuilder: (context, index) {
              final widgetId = order[index];
              final visible = !hiddenIds.contains(widgetId);
              return ListTile(
                key: Key('dashboard_customize_row_$widgetId'),
                leading: const Icon(Icons.drag_handle),
                title: Text(labels[widgetId] ?? widgetId),
                trailing: Checkbox(
                  key: Key('dashboard_customize_toggle_$widgetId'),
                  value: visible,
                  onChanged: (_) => onToggle(widgetId),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

/// Sélecteur de modèle d'ordonnance (#4074) : bottom sheet listant les
/// modèles du cabinet + le catalogue dentaire standard (modèles globaux,
/// #4073), groupés séparément.
class PrescriptionTemplatePicker extends StatelessWidget {
  const PrescriptionTemplatePicker({
    super.key,
    required this.loadTemplates,
  });

  final Future<List<PrescriptionTemplate>> Function() loadTemplates;

  /// Ouvre le picker ; retourne le modèle choisi, ou `null` si annulé.
  static Future<PrescriptionTemplate?> show(
    BuildContext context, {
    required Future<List<PrescriptionTemplate>> Function() loadTemplates,
  }) {
    return showModalBottomSheet<PrescriptionTemplate>(
      context: context,
      isScrollControlled: true,
      builder: (_) => PrescriptionTemplatePicker(loadTemplates: loadTemplates),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      key: const Key('prescription_template_picker'),
      child: FractionallySizedBox(
        heightFactor: 0.75,
        child: FutureBuilder<List<PrescriptionTemplate>>(
          future: loadTemplates(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final templates = snapshot.data!;
            final cabinetTemplates =
                templates.where((t) => !t.isGlobal).toList();
            final globalTemplates = templates.where((t) => t.isGlobal).toList();

            if (templates.isEmpty) {
              return const NubiaEmptyState(
                key: Key('prescription_template_empty'),
                icon: Icons.description_outlined,
                title: 'Aucun modèle disponible',
                subtitle: 'Créez un modèle depuis une ordonnance existante.',
              );
            }

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text('Modèles', style: theme.textTheme.titleMedium),
                const SizedBox(height: 12),
                if (cabinetTemplates.isNotEmpty) ...[
                  Text('Modèles du cabinet',
                      style: theme.textTheme.labelLarge?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 4),
                  for (final t in cabinetTemplates) _TemplateTile(template: t),
                  const SizedBox(height: 16),
                ],
                if (globalTemplates.isNotEmpty) ...[
                  Text('Catalogue dentaire standard',
                      style: theme.textTheme.labelLarge?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 4),
                  for (final t in globalTemplates) _TemplateTile(template: t),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _TemplateTile extends StatelessWidget {
  const _TemplateTile({required this.template});

  final PrescriptionTemplate template;

  @override
  Widget build(BuildContext context) {
    return ListRow(
      key: Key('prescription_template_${template.id}'),
      title: template.label,
      subtitle: '${template.items.length} ligne(s)',
      leading: const Icon(Icons.description_outlined, size: 22),
      onTap: () => Navigator.of(context).pop(template),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

/// Sélecteur de modèle de compte rendu (#4125) : bottom sheet listant les
/// modèles du cabinet (#4123/#4124), groupés selon leur pertinence pour le
/// premier acte CCAM de la séance — mêmes conventions que
/// `PrescriptionTemplatePicker` (#4074).
class CrTemplatePicker extends StatelessWidget {
  const CrTemplatePicker({
    super.key,
    required this.loadTemplates,
    this.firstActCcamCode,
  });

  final Future<List<CrTemplate>> Function() loadTemplates;

  /// Code CCAM du premier acte ajouté à la séance, s'il y en a un — sert
  /// uniquement à trier les modèles pertinents en tête de liste.
  final String? firstActCcamCode;

  /// Ouvre le picker ; retourne le modèle choisi, ou `null` si annulé.
  static Future<CrTemplate?> show(
    BuildContext context, {
    required Future<List<CrTemplate>> Function() loadTemplates,
    String? firstActCcamCode,
  }) {
    return showModalBottomSheet<CrTemplate>(
      context: context,
      isScrollControlled: true,
      builder: (_) => CrTemplatePicker(
        loadTemplates: loadTemplates,
        firstActCcamCode: firstActCcamCode,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      key: const Key('cr_template_picker'),
      child: FractionallySizedBox(
        heightFactor: 0.75,
        child: FutureBuilder<List<CrTemplate>>(
          future: loadTemplates(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final templates = snapshot.data!;

            if (templates.isEmpty) {
              return const NubiaEmptyState(
                key: Key('cr_template_empty'),
                icon: Icons.description_outlined,
                title: 'Aucun modèle disponible',
                subtitle: 'Créez un modèle de compte rendu pour ce cabinet.',
              );
            }

            final matching = firstActCcamCode == null
                ? <CrTemplate>[]
                : templates
                    .where((t) => t.ccamCode == firstActCcamCode)
                    .toList();
            final generic = templates.where((t) => t.ccamCode == null).toList();
            final others = templates
                .where(
                    (t) => t.ccamCode != null && t.ccamCode != firstActCcamCode)
                .toList();

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text('Modèles de compte rendu',
                    style: theme.textTheme.titleMedium),
                const SizedBox(height: 12),
                if (matching.isNotEmpty) ...[
                  Text('Pour cet acte',
                      style: theme.textTheme.labelLarge?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 4),
                  for (final t in matching) _TemplateTile(template: t),
                  const SizedBox(height: 16),
                ],
                if (generic.isNotEmpty) ...[
                  Text('Modèles génériques',
                      style: theme.textTheme.labelLarge?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 4),
                  for (final t in generic) _TemplateTile(template: t),
                  const SizedBox(height: 16),
                ],
                if (others.isNotEmpty) ...[
                  Text('Autres modèles',
                      style: theme.textTheme.labelLarge?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 4),
                  for (final t in others) _TemplateTile(template: t),
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

  final CrTemplate template;

  @override
  Widget build(BuildContext context) {
    return ListRow(
      key: Key('cr_template_${template.id}'),
      title: template.title,
      subtitle: template.ccamCode ?? 'Générique',
      leading: const Icon(Icons.description_outlined, size: 22),
      onTap: () => Navigator.of(context).pop(template),
    );
  }
}

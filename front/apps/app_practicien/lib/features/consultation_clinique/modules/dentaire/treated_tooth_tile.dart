import 'package:flutter/material.dart';

import 'tooth_anatomy_labels.dart';

/// Tuile « Dent traitée » du contexte clinique (maquette : pastille « 26 » +
/// « 1ère molaire · maxillaire G »). Affiche la dent sélectionnée, ou à
/// défaut la dernière dent traitée cette séance.
class TreatedToothTile extends StatelessWidget {
  const TreatedToothTile({super.key, required this.tooth});

  final String tooth;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final anatomy = toothAnatomyLabel(tooth);

    return Container(
      key: const Key('treated_tooth_tile'),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: cs.primaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: Text(
              tooth,
              style: textTheme.titleSmall?.copyWith(
                color: cs.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Dent traitée',
                  style: textTheme.bodySmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                if (anatomy != null)
                  Text(
                    anatomy,
                    key: const Key('treated_tooth_anatomy'),
                    style: textTheme.bodySmall
                        ?.copyWith(color: cs.onSurfaceVariant),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'euro_format.dart';

/// Ligne d'acte de la séance (maquette : pastille ✔/⏱, libellé,
/// « CODE · dent NN » en chiffres tabulaires, montant à droite).
///
/// [highlighted] surligne l'acte courant — par convention le dernier ajouté
/// (#4139, `session.acts` trié `created_at ASC` côté back).
class SessionActRow extends StatelessWidget {
  const SessionActRow({
    super.key,
    required this.act,
    this.highlighted = false,
  });

  final ClinicalAct act;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final subtitle = act.tooth != null && act.tooth!.isNotEmpty
        ? '${act.ccamCode} · Dent ${act.tooth}'
        : act.ccamCode;

    return Container(
      key: Key('act_${act.id}'),
      color: highlighted ? cs.primaryContainer.withValues(alpha: 0.35) : null,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          CircleAvatar(
            radius: 13,
            backgroundColor: highlighted ? cs.surface : cs.primary,
            child: Icon(
              highlighted ? Icons.schedule : Icons.check,
              size: 15,
              color: highlighted ? cs.primary : cs.onPrimary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  act.label,
                  style: textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w500),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  subtitle,
                  style: textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            act.amountCents != null ? formatEuros(act.amountCents!) : 'incluse',
            style: act.amountCents != null
                ? textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  )
                : textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

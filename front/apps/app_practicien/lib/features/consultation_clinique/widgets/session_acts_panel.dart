import 'package:flutter/material.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'euro_format.dart';
import 'session_act_row.dart';

/// Panneau « Actes de la séance » (maquette : en-tête avec total, lignes
/// d'actes, dernier acte surligné comme acte courant).
///
/// Rendu en colonne (non scrollable) : le scroll appartient à la colonne
/// centrale de la vue.
class SessionActsPanel extends StatelessWidget {
  const SessionActsPanel({super.key, required this.session});

  final ClinicalSession session;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final acts = session.acts;
    final totalCents =
        acts.fold<int>(0, (sum, a) => sum + (a.amountCents ?? 0));

    return NubiaCard(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        key: const Key('session_acts_panel'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Actes de la séance',
                    style: textTheme.titleSmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    '${acts.length} acte(s) CCAM · ${formatEuros(totalCents)}',
                    key: const Key('session_acts_total'),
                    style: textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          if (acts.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: NubiaEmptyState(
                key: Key('consultation_empty'),
                icon: Icons.medical_services_outlined,
                title: 'Aucun acte enregistré',
                subtitle: 'Recherchez un acte CCAM pour l\'ajouter.',
              ),
            )
          else
            for (var i = 0; i < acts.length; i++) ...[
              if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
              SessionActRow(
                act: acts[i],
                // Dernier ajouté = acte courant (#4139) — surligné tant que
                // la séance est en cours.
                highlighted: !session.isFinished && i == acts.length - 1,
              ),
            ],
        ],
      ),
    );
  }
}

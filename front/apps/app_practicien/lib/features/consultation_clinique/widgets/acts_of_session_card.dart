// Quoi : encart « Actes de la séance » (en-tête + compteur, liste
// d'`ActTile` ou état vide, pied « Total des actes enregistrés »).
// Quand : rendu par `CenterColumn` dans l'écran consultation au fauteuil.
// Pourquoi : extrait de `consultation_clinique_page.dart` (#4954) pour
// redescendre ce fichier sous le plafond de taille CLAUDE.md — aucun
// changement de rendu, mêmes Keys (`consultation_acts_card`,
// `consultation_empty`, `consultation_acts_list`, `consultation_acts_total`,
// `consultation_acts_count_badge`).
// Modes d'échec : aucun — widget purement présentationnel ; le total affiché
// vient de [sessionTotalCents], seule source de vérité partagée avec la
// barre d'identité patient.
import 'package:flutter/material.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'act_tile.dart';
import 'consultation_format_utils.dart';

/// Encart « Actes de la séance » (#4952, maquette design-v2) : en-tête icône
/// + titre + badge compteur (`session.acts.length`), liste d'actes ou état
/// vide (`consultation_empty` conservé), et pied « Total des actes
/// enregistrés » repris de [sessionTotalCents] — même valeur que le
/// « Total séance » de la barre d'identité.
class ActsOfSessionCard extends StatelessWidget {
  const ActsOfSessionCard({super.key, required this.session});

  final ClinicalSession session;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final acts = session.acts;
    return NubiaCard(
      key: const Key('consultation_acts_card'),
      padding: EdgeInsets.zero,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Icon(Icons.list_alt, size: 20, color: cs.primary),
                const SizedBox(width: 8),
                Expanded(
                  child:
                      Text('Actes de la séance', style: textTheme.titleSmall),
                ),
                _ActsCountBadge(count: acts.length),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, acts.isEmpty ? 16 : 0),
            child: acts.isEmpty
                ? const NubiaEmptyState(
                    key: Key('consultation_empty'),
                    icon: Icons.medical_services_outlined,
                    title: 'Aucun acte enregistré',
                    subtitle: 'Recherchez un acte CCAM pour l\'ajouter.',
                  )
                : ListView.builder(
                    key: const Key('consultation_acts_list'),
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: acts.length,
                    itemBuilder: (context, i) => ActTile(act: acts[i]),
                  ),
          ),
          if (acts.isNotEmpty)
            _ActsSessionFooterTotal(totalCents: sessionTotalCents(session)),
        ],
      ),
    );
  }
}

/// Badge compteur d'actes de l'en-tête (pastille grise, ex. « 3 ») — même
/// style que les chips gris déjà utilisés sur cet écran (`_CcamCodeChip`,
/// `_ToothBadge` sans dent, `act_tile.dart`) : fond `borderSubtle`, texte
/// `textTertiary`.
class _ActsCountBadge extends StatelessWidget {
  const _ActsCountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    return Container(
      key: const Key('consultation_acts_count_badge'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: tokens.borderSubtle,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '$count',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: tokens.textTertiary,
              fontWeight: FontWeight.w600,
              fontFeatures: tabularFigures,
            ),
      ),
    );
  }
}

/// Pied de liste « Total des actes enregistrés » (#4952, maquette design-v2)
/// : bandeau gris clair pleine largeur, montant en gras et chiffres
/// tabulaires (euros français via [formatQuoteCents]).
class _ActsSessionFooterTotal extends StatelessWidget {
  const _ActsSessionFooterTotal({required this.totalCents});

  final int totalCents;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    final textTheme = Theme.of(context).textTheme;
    return Container(
      key: const Key('consultation_acts_total'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: tokens.borderSubtle,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Total des actes enregistrés',
              style: textTheme.bodyMedium?.copyWith(color: tokens.textTertiary),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            formatQuoteCents(totalCents, alwaysShowDecimals: true),
            style: textTheme.titleMedium?.copyWith(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              fontFeatures: tabularFigures,
            ),
          ),
        ],
      ),
    );
  }
}

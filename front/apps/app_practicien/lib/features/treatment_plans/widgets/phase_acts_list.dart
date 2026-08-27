import 'package:flutter/material.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

/// Une ligne d'acte affichée par [PhaseActsList] (#5015, maquette design-v2
/// point 2, `.act`). Vue purement présentationnelle, sans dépendance au
/// modèle domaine `TreatmentAct` (ticket domaine « actes rattachés à une
/// phase », pas encore livré : `TreatmentPhase` ne porte aucune liste
/// d'actes pour l'instant, donc l'appelant passe une liste vide en
/// attendant — voir `treatment_plans_page.dart`).
class PhaseActRow {
  const PhaseActRow({
    required this.id,
    required this.tooth,
    required this.label,
    required this.ccamCode,
    required this.subtitle,
    required this.amountCents,
  });

  final String id;

  /// Numéro de dent (ex. « 26 »). `null`/vide ⇒ badge `.tb.no` gris « — ».
  final String? tooth;
  final String label;
  final String ccamCode;

  /// Sous-titre gris `.l2` (ex. « Réalisé le 22/07 », « Séance du 11/08 ·
  /// en cours », « À programmer », « Après cicatrisation · délai
  /// laboratoire 8 j »).
  final String subtitle;
  final int amountCents;
}

/// Liste des actes d'une phase (#5015, maquette design-v2 point 2, `.act`) :
/// une ligne par acte sous l'en-tête de la carte de phase. Liste vide ⇒ rien
/// n'est rendu (pas de titre de section ni de séparateur) — une phase sans
/// acte ne casse pas la carte.
class PhaseActsList extends StatelessWidget {
  const PhaseActsList({super.key, required this.acts});

  final List<PhaseActRow> acts;

  @override
  Widget build(BuildContext context) {
    if (acts.isEmpty) return const SizedBox.shrink();
    return Column(
      children: [
        for (final act in acts) _ActRow(act: act),
      ],
    );
  }
}

class _ActRow extends StatelessWidget {
  const _ActRow({required this.act});

  final PhaseActRow act;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    return Padding(
      key: Key('treatment_phase_act_${act.id}'),
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _ToothBadge(tooth: act.tooth),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        act.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodyMedium,
                      ),
                    ),
                    const SizedBox(width: 6),
                    _CcamCodeChip(code: act.ccamCode),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  act.subtitle,
                  style:
                      textTheme.bodySmall?.copyWith(color: tokens.textTertiary),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            NubiaMoney.formatCents(act.amountCents),
            style: textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
              fontFeatures: tabularFigures,
            ),
          ),
        ],
      ),
    );
  }
}

/// Badge dent (ex. « 26 ») affiché à gauche de la ligne d'acte, ou « — » en
/// gris si l'acte n'a pas de dent associée (maquette design-v2 `.tb` : carré
/// 32px, fond `brand50`, bordure `brand100`, texte émeraude ; variante
/// `.tb.no` grise si pas de dent). Même patron que `ActTile._ToothBadge`
/// (consultation clinique, #4950/#4967), tailles différentes (32 ici, 38
/// là-bas — valeurs distinctes des deux maquettes).
class _ToothBadge extends StatelessWidget {
  const _ToothBadge({required this.tooth});
  final String? tooth;

  static const _size = 32.0;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    final hasTooth = tooth != null && tooth!.isNotEmpty;

    return Container(
      width: _size,
      height: _size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: hasTooth ? cs.primaryContainer : tokens.borderSubtle,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: hasTooth ? NubiaColors.brand100 : tokens.borderDefault,
        ),
      ),
      child: Text(
        hasTooth ? tooth! : '—',
        style: textTheme.labelMedium?.copyWith(
          color: hasTooth ? cs.onPrimaryContainer : tokens.textTertiary,
          fontWeight: FontWeight.w600,
          fontFeatures: tabularFigures,
        ),
      ),
    );
  }
}

/// Chip code CCAM en monospace, affiché juste après le libellé d'acte
/// (maquette design-v2 point 2). Même patron que `ActTile._CcamCodeChip`
/// (consultation clinique, #4950).
class _CcamCodeChip extends StatelessWidget {
  const _CcamCodeChip({required this.code});
  final String code;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: tokens.borderSubtle,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: tokens.borderDefault),
      ),
      child: Text(
        code,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: tokens.textTertiary,
              fontFamily: 'monospace',
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

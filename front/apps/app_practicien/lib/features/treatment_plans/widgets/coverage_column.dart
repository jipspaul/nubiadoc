// Quoi : colonne « Couverture financière » (design-v2, écran PC praticien ·
// plan de traitement, #6626) — synthèse des montants du plan, alerte + CTA
// contextuel sur la première phase non couverte par un devis signé, puis
// « Devis rattachés ».
// Quand : rendue par `_PlansSplitView` (`treatment_plans_page.dart`)
// uniquement en layout 3 colonnes (largeur disponible ≥
// kCoverageColumnBreakpoint, même logique que `kThreeColumnBreakpoint` de
// l'écran consultation, #4935).
// Pourquoi : maquette
// `design/mockups/v2/Ecrans PC - Praticien et Pharmacie.html`, écran
// « Plan de traitement » — sur 1440×900 le trou de couverture financière
// n'était affiché nulle part et « Générer le devis » restait un CTA
// générique en en-tête, sans lien avec la phase concernée (#6626).
// Modes d'échec : « Prochaines séances » de la maquette n'est pas rendue ici
// — aucun rendez-vous n'est rattaché à `TreatmentPlan`/`TreatmentPhase` côté
// domaine praticien (seule l'entité patient `PatientTreatmentPlan` porte
// `nextAppointmentAt`, hors périmètre de cet écran) ; à ajouter quand ce
// ticket domaine existera.
import 'package:flutter/material.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

/// Largeur disponible (corps de `ProShell`, jamais `MediaQuery`) à partir de
/// laquelle la colonne « Couverture financière » apparaît — même calcul que
/// `kThreeColumnBreakpoint` (consultation_clinique, #6386) : 1440 (fenêtre
/// cible de la maquette) − 251 (rail 250 px + séparateur 1 px de
/// `ProShell`) = 1189.
const kCoverageColumnBreakpoint = 1189.0;
const kCoverageColumnWidth = 340.0;

/// Un devis rattaché à une ou plusieurs phases du plan (#6626) — regroupe
/// les [TreatmentPhase] partageant le même
/// [TreatmentPhaseQuoteRef.quoteNumber].
class _AttachedQuote {
  _AttachedQuote({required this.ref, required this.phases});

  final TreatmentPhaseQuoteRef ref;
  final List<TreatmentPhase> phases;
}

/// Rang 1-indexé de chaque phase dans l'ordre du plan (#6913) — `position`
/// est l'entier d'ordonnancement brut stocké en base, ni 1-indexé ni
/// contigu, donc impropre à l'affichage (« la phase 0 », « la phase 9 »
/// sur un plan de 2 phases). La maquette numérote les phases 1..N dans
/// l'ordre de [TreatmentPlan.phases].
Map<String, int> _phaseRanks(List<TreatmentPhase> phases) => {
      for (final (index, phase) in phases.indexed) phase.id: index + 1,
    };

/// Première phase non engagée financièrement (aucun devis signé) — celle
/// qui explique [TreatmentPlan.remainingToQuoteCents], cohérent avec le
/// calcul de [TreatmentPlan.engagedCents] (phases dont `quoteRef.signedAt`
/// est renseigné). Ignore les phases sans acte chiffré (`totalCents == 0`,
/// #7989) : elles ne peuvent produire aucun devis valide, même quand une
/// phase suivante porte, elle, le montant qui justifie
/// `remainingToQuoteCents > 0`.
TreatmentPhase? _firstUnengagedPhase(List<TreatmentPhase> phases) {
  for (final phase in phases) {
    if (phase.quoteRef?.signedAt == null && phase.totalCents > 0) {
      return phase;
    }
  }
  return null;
}

List<_AttachedQuote> _attachedQuotes(List<TreatmentPhase> phases) {
  final byNumber = <String, _AttachedQuote>{};
  for (final phase in phases) {
    final ref = phase.quoteRef;
    if (ref == null) continue;
    final existing = byNumber[ref.quoteNumber];
    if (existing == null) {
      byNumber[ref.quoteNumber] = _AttachedQuote(ref: ref, phases: [phase]);
    } else {
      existing.phases.add(phase);
    }
  }
  return byNumber.values.toList();
}

class CoverageColumn extends StatelessWidget {
  const CoverageColumn({
    super.key,
    required this.plan,
    required this.onGenerateQuote,
  });

  final TreatmentPlan plan;

  /// Appelé avec la phase non couverte concernée (#6914) — le CTA porte son
  /// rang dans le plan (#6913) et doit produire un devis pour *cette* phase
  /// précisément, pas une navigation générique sans contexte.
  final ValueChanged<TreatmentPhase> onGenerateQuote;

  @override
  Widget build(BuildContext context) {
    final phases = plan.phases;
    // Alerte + CTA uniquement si un montant réel reste sans engagement — une
    // phase sans acte chiffré n'a rien à « générer en devis » (même cadrage
    // que `PlanFooter._UncoveredWarning`, remainingToQuoteCents > 0).
    final uncoveredPhase = plan.remainingToQuoteCents > 0
        ? _firstUnengagedPhase(phases)
        : null;
    final percentUncovered = plan.totalCents == 0
        ? 0
        : (plan.remainingToQuoteCents * 100 / plan.totalCents).round();
    final quotes = _attachedQuotes(phases);
    final phaseRanks = _phaseRanks(phases);

    return Container(
      key: const Key('treatment_plan_coverage_column'),
      width: kCoverageColumnWidth,
      decoration: const BoxDecoration(
        color: NubiaColors.n0,
        border: Border(left: BorderSide(color: NubiaColors.n200)),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionHeader(
              icon: Icons.account_balance_wallet,
              title: 'Couverture financière',
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _FinRow(label: 'Total du plan', amountCents: plan.totalCents),
                  const SizedBox(height: 6),
                  _FinRow(
                    label: 'Réalisé et facturé',
                    amountCents: plan.realizedCents,
                  ),
                  const SizedBox(height: 6),
                  _FinRow(
                    label: 'Engagé (devis signé)',
                    amountCents: plan.engagedCents,
                  ),
                  const SizedBox(height: 8),
                  _FinRow(
                    key: Key('treatment_plan_coverage_uncovered_${plan.id}'),
                    label: 'Non couvert par un devis',
                    amountCents: plan.remainingToQuoteCents,
                    emphasize: true,
                  ),
                  if (uncoveredPhase != null) ...[
                    const SizedBox(height: 11),
                    _UncoveredPhaseAlert(
                      key: Key('treatment_plan_coverage_alert_${plan.id}'),
                      phaseRank: phaseRanks[uncoveredPhase.id]!,
                      percentUncovered: percentUncovered,
                    ),
                    const SizedBox(height: 11),
                    SizedBox(
                      width: double.infinity,
                      child: NubiaButton(
                        key: Key(
                          'treatment_plan_coverage_generate_quote_${plan.id}',
                        ),
                        icon: Icons.description,
                        label:
                            'Générer le devis de la phase ${phaseRanks[uncoveredPhase.id]}',
                        onPressed: () => onGenerateQuote(uncoveredPhase),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (quotes.isNotEmpty) ...[
              _SectionHeader(
                icon: Icons.receipt_long,
                title: 'Devis rattachés',
                count: quotes.length,
                topBorder: true,
              ),
              for (final quote in quotes)
                _QuoteRow(
                  key: Key(
                    'treatment_plan_coverage_quote_${quote.ref.quoteNumber}',
                  ),
                  quote: quote,
                  phaseRanks: phaseRanks,
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.icon,
    required this.title,
    this.count,
    this.topBorder = false,
  });

  final IconData icon;
  final String title;
  final int? count;
  final bool topBorder;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        border: Border(
          top: topBorder
              ? const BorderSide(color: NubiaColors.n200)
              : BorderSide.none,
          bottom: const BorderSide(color: NubiaColors.n200),
        ),
      ),
      child: Row(
        children: [
          Icon(icon, size: 17, color: NubiaColors.n500),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: textTheme.titleSmall,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (count != null) ...[
            const SizedBox(width: 8),
            NubiaBadge.count(count: count!),
          ],
        ],
      ),
    );
  }
}

class _FinRow extends StatelessWidget {
  const _FinRow({
    super.key,
    required this.label,
    required this.amountCents,
    this.emphasize = false,
  });

  final String label;
  final int amountCents;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: emphasize
                ? textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)
                : textTheme.bodyMedium?.copyWith(color: NubiaColors.n600),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Text(
          NubiaMoney.formatCents(amountCents),
          style: (emphasize ? textTheme.titleMedium : textTheme.bodyMedium)
              ?.copyWith(
            fontWeight: FontWeight.w700,
            fontFeatures: tabularFigures,
            color: emphasize && amountCents > 0
                ? Theme.of(context).extension<NubiaTokens>()!.warningFg
                : null,
          ),
        ),
      ],
    );
  }
}

class _UncoveredPhaseAlert extends StatelessWidget {
  const _UncoveredPhaseAlert({
    super.key,
    required this.phaseRank,
    required this.percentUncovered,
  });

  final int phaseRank;
  final int percentUncovered;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: tokens.warningBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: NubiaColors.warningBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error, size: 16, color: tokens.warningFg),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: textTheme.bodySmall?.copyWith(color: tokens.warningFg),
                children: [
                  TextSpan(
                    text: 'La phase $phaseRank n\'est couverte par '
                        'aucun devis.',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  TextSpan(
                    text: ' $percentUncovered % du montant du plan reste '
                        'sans engagement.',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuoteRow extends StatelessWidget {
  const _QuoteRow({super.key, required this.quote, required this.phaseRanks});

  final _AttachedQuote quote;
  final Map<String, int> phaseRanks;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final ref = quote.ref;
    final phaseLabel = quote.phases.length > 1
        ? 'Phases ${quote.phases.map((p) => phaseRanks[p.id]).join(' et ')}'
        : 'Phase ${phaseRanks[quote.phases.first.id]}';
    final signedAt = ref.signedAt;
    final subtitle = [
      phaseLabel,
      if (signedAt != null) 'signé le ${_formatDate(signedAt)}',
      if (ref.depositPaid) 'acompte réglé',
    ].join(' · ');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: NubiaColors.n100)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ref.quoteNumber,
                  style: textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 1),
                Text(
                  subtitle,
                  style:
                      textTheme.bodySmall?.copyWith(color: NubiaColors.n500),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          StatusPill(
            label: signedAt != null ? 'Signé' : 'En attente de signature',
            variant:
                signedAt != null ? StatusPillVariant.success : StatusPillVariant.info,
          ),
        ],
      ),
    );
  }
}

String _formatDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';

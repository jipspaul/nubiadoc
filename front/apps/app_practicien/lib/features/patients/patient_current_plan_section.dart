//! Encart « Plan en cours » (#4977, maquette design-v2
//! `praticien-dossier-patient.png`, colonne droite `.bx`) — résumé du plan
//! de traitement actif du patient (avancement, montant, trou de couverture)
//! visible directement dans le dossier, sans naviguer vers l'écran plan
//! complet (`TreatmentPlansPage`, `/patients/:id/treatment-plans`).
//!
//! Réutilise `ListTreatmentPlansUseCase`/`TreatmentPlan` — même source que
//! `TreatmentPlansPage`/`_TreatmentPlansCard` (`patient_fiche.dart`) — plutôt
//! que de dupliquer la logique d'agrégation des montants de plan (#5013).

import 'package:dartz/dartz.dart' hide State;
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'async_section_state.dart';

/// Plan « en cours » = premier plan `status == 'in_progress'` du patient
/// (même vocabulaire que `treatmentPlanStatusLabels`). Aucun plan en cours
/// (liste vide ou aucun `in_progress`) → encart absent plutôt qu'une carte
/// vide : la liste complète des plans reste sur `TreatmentPlansPage`.
class PatientCurrentPlanSection extends StatefulWidget {
  const PatientCurrentPlanSection({super.key, required this.patientId});

  final String patientId;

  @override
  State<PatientCurrentPlanSection> createState() =>
      _PatientCurrentPlanSectionState();
}

class _PatientCurrentPlanSectionState extends State<PatientCurrentPlanSection>
    with AsyncSectionState<List<TreatmentPlan>, PatientCurrentPlanSection> {
  @override
  Future<Either<Failure, List<TreatmentPlan>>> fetchSection() =>
      GetIt.instance<ListTreatmentPlansUseCase>()(widget.patientId);

  TreatmentPlan? get _currentPlan {
    final plans = data;
    if (plans == null) return null;
    for (final plan in plans) {
      if (plan.status == 'in_progress') return plan;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (error != null) {
      return NubiaCard(
        key: const Key('patient_current_plan_error'),
        child: NubiaErrorWidget(message: error!, onRetry: loadSection),
      );
    }
    if (loading) {
      return const NubiaSkeletonLoader(
        key: Key('patient_current_plan_loading'),
        height: 132,
        borderRadius: 12,
      );
    }
    final plan = _currentPlan;
    if (plan == null) return const SizedBox.shrink();
    return _CurrentPlanCard(
      key: Key('patient_current_plan_${plan.id}'),
      plan: plan,
    );
  }
}

/// Carte `.bx` de la maquette : en-tête (icône + « Plan en cours » + badge
/// « phase X / Y »), titre du plan, barre de progression, ligne
/// avancement/montant, et — quand une phase n'est pas couverte par un devis
/// signé — l'encart d'alerte `.gap`.
class _CurrentPlanCard extends StatelessWidget {
  const _CurrentPlanCard({super.key, required this.plan});

  final TreatmentPlan plan;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final phases = plan.phases;
    final stepCount = phases.length;
    final doneCount = phases.where((phase) => phase.status == 'done').length;
    // Étape courante = la première phase non terminée (#4977) — même
    // convention que `_PlanProgressSummary`/`PlanCard` (app_patient) :
    // les phases terminées sont contiguës depuis le début du plan.
    final currentStep =
        stepCount == 0 ? 0 : (doneCount + 1).clamp(1, stepCount);
    final donePlural = doneCount > 1 ? 's' : '';
    final uncoveredCents = plan.remainingToQuoteCents;

    return NubiaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.assignment, size: 20, color: cs.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Plan en cours', style: textTheme.titleMedium),
              ),
              if (stepCount > 0)
                StatusPill(
                  key: Key('patient_current_plan_step_badge_${plan.id}'),
                  label: 'phase $currentStep / $stepCount',
                  variant: StatusPillVariant.info,
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            plan.title,
            key: Key('patient_current_plan_title_${plan.id}'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.titleSmall,
          ),
          if (stepCount > 0) ...[
            const SizedBox(height: 10),
            _CurrentPlanProgressBar(
              key: Key('patient_current_plan_progress_${plan.id}'),
              stepCount: stepCount,
              filledCount: currentStep,
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    '$doneCount phase$donePlural terminée$donePlural sur '
                    '$stepCount',
                    key:
                        Key('patient_current_plan_progress_label_${plan.id}'),
                    style: textTheme.bodySmall
                        ?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  NubiaMoney.formatCents(plan.totalCents),
                  key: Key('patient_current_plan_total_${plan.id}'),
                  style: textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    fontFeatures: tabularFigures,
                  ),
                ),
              ],
            ),
          ],
          if (uncoveredCents > 0) ...[
            const SizedBox(height: 10),
            _UncoveredGapAlert(
              key: Key('patient_current_plan_gap_${plan.id}'),
              amountCents: uncoveredCents,
              uncoveredPhasePosition: _firstUncoveredPhasePosition(phases),
            ),
          ],
        ],
      ),
    );
  }
}

/// Première phase dont le devis n'est pas signé (mentionnée dans l'encart
/// `.gap`) — `null` si toutes les phases sont couvertes (l'encart ne
/// s'affiche alors pas, `uncoveredCents == 0`).
int? _firstUncoveredPhasePosition(List<TreatmentPhase> phases) {
  for (final phase in phases) {
    if (phase.quoteRef?.signedAt == null) return phase.position;
  }
  return null;
}

/// Barre `.bar` : un segment par phase, plein `--brand600` (`.on`) pour les
/// phases atteintes (terminées + phase courante), `n200` pour celles à
/// venir — 2 états, pas de nuance intermédiaire (maquette v2 §.bx).
class _CurrentPlanProgressBar extends StatelessWidget {
  const _CurrentPlanProgressBar({
    super.key,
    required this.stepCount,
    required this.filledCount,
  });

  final int stepCount;
  final int filledCount;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 6,
      child: Row(
        children: [
          for (var i = 0; i < stepCount; i++) ...[
            if (i > 0) const SizedBox(width: 3),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: i < filledCount
                      ? NubiaColors.brand600
                      : NubiaColors.n200,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Encart `.gap` de la maquette : fond `warnBg`, icône `error` — le montant
/// du plan qu'aucun devis signé ne couvre encore, avec la phase bloquante.
class _UncoveredGapAlert extends StatelessWidget {
  const _UncoveredGapAlert({
    super.key,
    required this.amountCents,
    required this.uncoveredPhasePosition,
  });

  final int amountCents;
  final int? uncoveredPhasePosition;

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
          Icon(Icons.error, size: 18, color: tokens.warningFg),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: textTheme.bodySmall?.copyWith(color: tokens.warningFg),
                children: [
                  TextSpan(
                    text: '${NubiaMoney.formatCents(amountCents)} sans devis',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  TextSpan(
                    text: uncoveredPhasePosition != null
                        ? " — la phase $uncoveredPhasePosition n'a pas été "
                            'acceptée par le patient.'
                        : '.',
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

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import '../../router/app_router.dart';
import 'treatment_plans_bloc.dart';
import 'widgets/phase_timeline.dart';
import 'widgets/plan_cost_block.dart';
import 'widgets/treatment_plan_format_utils.dart';

const _phaseStatusLabels = {
  'requested': 'Demandée',
  'confirmed': 'Confirmée',
  'in_progress': 'En cours',
  'done': 'Réalisée',
};

const _phaseStatusVariants = {
  'requested': StatusPillVariant.info,
  'confirmed': StatusPillVariant.warning,
  'in_progress': StatusPillVariant.warning,
  'done': StatusPillVariant.success,
};

/// Libellés du bloc `.amt` selon l'état de couverture financière de la
/// phase, verbatim maquette (#5298).
const _phaseCoverageLabels = {
  PatientTreatmentPlanPhaseCoverage.paid: 'Réglé',
  PatientTreatmentPlanPhaseCoverage.covered: 'Couvert par votre devis signé',
  PatientTreatmentPlanPhaseCoverage.estimated: 'Estimation',
};

/// Ligne `.dt` (icône + texte) au-dessus du bloc `.amt` — uniquement quand
/// une date de séance existe pour la phase ; pas de donnée fabriquée pour
/// les phases pas encore programmées (#5298).
String? _phaseDateLabel(PatientTreatmentPlanPhase phase) {
  final appointmentAt = phase.appointmentAt;
  if (appointmentAt == null) return null;
  final local = appointmentAt.toLocal();

  switch (phase.status) {
    case 'done':
      return 'Réalisée le ${formatTreatmentPlanDayMonth(local)}';
    case 'in_progress':
      final now = DateTime.now();
      final isToday = local.year == now.year &&
          local.month == now.month &&
          local.day == now.day;
      final time = formatTreatmentPlanTime(local);
      return isToday
          ? 'Séance aujourd\'hui à $time'
          : 'Séance le ${formatTreatmentPlanDayMonth(local)} à $time';
    default:
      return null;
  }
}

/// Détail d'un plan de traitement (#4261) : phases + actes.
class PatientTreatmentPlanDetailPage extends StatelessWidget {
  const PatientTreatmentPlanDetailPage({super.key, required this.planId});

  final String planId;

  @override
  Widget build(BuildContext context) {
    return BlocProvider<PatientTreatmentPlanDetailCubit>(
      create: (_) =>
          GetIt.instance<PatientTreatmentPlanDetailCubit>()..load(planId),
      child: const PatientTreatmentPlanDetailBody(),
    );
  }
}

/// Corps de l'écran — public pour les tests widget.
class PatientTreatmentPlanDetailBody extends StatelessWidget {
  const PatientTreatmentPlanDetailBody({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Plan de traitement')),
      body: BlocBuilder<PatientTreatmentPlanDetailCubit,
          PatientTreatmentPlanDetailState>(
        builder: (context, state) {
          switch (state) {
            case PatientTreatmentPlanDetailLoading():
              return const _PlanDetailSkeleton();
            case PatientTreatmentPlanDetailError(:final message):
              return NubiaErrorWidget(message: message);
            case PatientTreatmentPlanDetailLoaded(:final plan):
              return _PlanDetailView(plan: plan);
          }
        },
      ),
    );
  }
}

class _PlanDetailSkeleton extends StatelessWidget {
  const _PlanDetailSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: const Key('treatment_plan_detail_loading'),
      padding: const EdgeInsets.all(16),
      children: const [
        NubiaSkeletonLoader(height: 24, width: 220),
        SizedBox(height: 16),
        NubiaSkeletonLoader(height: 80, borderRadius: 12),
        SizedBox(height: 24),
        NubiaSkeletonLoader(height: 20, width: 100),
        SizedBox(height: 12),
        _PhaseSkeletonCard(),
        SizedBox(height: 12),
        _PhaseSkeletonCard(),
        SizedBox(height: 12),
        _PhaseSkeletonCard(),
      ],
    );
  }
}

class _PhaseSkeletonCard extends StatelessWidget {
  const _PhaseSkeletonCard();

  @override
  Widget build(BuildContext context) {
    return const NubiaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              NubiaSkeletonLoader(height: 16, width: 140),
              NubiaSkeletonLoader(height: 22, width: 72, borderRadius: 999),
            ],
          ),
          SizedBox(height: 12),
          NubiaSkeletonLoader(height: 12, width: 180),
        ],
      ),
    );
  }
}

class _PlanDetailView extends StatelessWidget {
  const _PlanDetailView({required this.plan});

  final PatientTreatmentPlan plan;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    final totalCents = plan.totalCostCents;
    final phases = [...plan.phases]
      ..sort((a, b) => a.position.compareTo(b.position));

    return SingleChildScrollView(
      key: const Key('treatment_plan_detail_loaded'),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(plan.title, style: textTheme.titleLarge),
          const SizedBox(height: 16),
          if (totalCents != null) PlanCostBlock(plan: plan),
          const SizedBox(height: 24),
          Text(
            'LES ÉTAPES DE VOTRE SOIN',
            style: textTheme.labelSmall?.copyWith(
              color: tokens.textTertiary,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 12),
          if (phases.isEmpty)
            const NubiaEmptyState(
              key: Key('treatment_plan_phases_empty'),
              icon: Icons.timeline_outlined,
              title: 'Aucune phase pour le moment',
            )
          else
            PhaseTimeline(
              children: [
                for (final (index, phase) in phases.indexed)
                  PhaseStep(
                    key: Key('treatment_plan_phase_${phase.id}'),
                    status: phase.status,
                    number: index + 1,
                    isLast: index == phases.length - 1,
                    card: _PhaseCard(phase: phase),
                  ),
              ],
            ),
          const SizedBox(height: 16),
          const _EstimatedAmountsNotice(),
        ],
      ),
    );
  }
}

/// Carte `.bd` d'une phase — statut, description patient, actes, date/
/// échéance, montant, et éventuels bandeau devis/CTA rendez-vous. Porte
/// `.card.now` (ombre + bordure accentuée) quand la phase est en cours
/// (#5296). Maquette : `design/v2-screens/patient-mon-plan-de-soins.png`.
class _PhaseCard extends StatelessWidget {
  const _PhaseCard({required this.phase});

  final PatientTreatmentPlanPhase phase;

  bool get _isNow => phase.status == 'in_progress';

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(child: Text(phase.title, style: textTheme.titleSmall)),
            StatusPill(
              label: _phaseStatusLabels[phase.status] ?? phase.status,
              variant:
                  _phaseStatusVariants[phase.status] ?? StatusPillVariant.info,
            ),
          ],
        ),
        if (phase.description != null) ...[
          const SizedBox(height: 4),
          Text(
            phase.description!,
            style: const TextStyle(
              fontSize: 13,
              height: 19 / 13,
              color: NubiaColors.n600,
            ),
          ),
        ],
        if (phase.items.isNotEmpty) ...[
          const SizedBox(height: 8),
          for (final item in phase.items)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(child: Text(item.label)),
                  Text(formatTreatmentPlanCents(item.unitAmountCents)),
                ],
              ),
            ),
        ],
        if (_phaseDateLabel(phase) != null) ...[
          const SizedBox(height: 12),
          _PhaseDateRow(label: _phaseDateLabel(phase)!),
        ],
        _PhaseAmountRow(phase: phase),
        if (phase.pendingQuoteId != null) ...[
          const SizedBox(height: 12),
          _PendingQuoteBanner(
            key: Key('phase_${phase.id}_pending_quote_banner'),
            sentAt: phase.pendingQuoteSentAt,
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: NubiaButton(
              key: Key('phase_${phase.id}_quote_cta'),
              label: 'Consulter et signer le devis',
              icon: Icons.draw,
              onPressed: () => context.push(
                  '${AppRouter.financial}?id=${phase.pendingQuoteId}'),
            ),
          ),
        ],
        if (phase.status == 'in_progress' && phase.appointmentId != null) ...[
          const SizedBox(height: 8),
          NubiaButton(
            key: Key('phase_${phase.id}_appointment_cta'),
            label: 'Voir mon rendez-vous',
            variant: NubiaButtonVariant.secondary,
            size: NubiaButtonSize.sm,
            icon: Icons.event,
            onPressed: () => context
                .push('${AppRouter.mesRdv}?id=${phase.appointmentId}'),
          ),
        ],
      ],
    );

    if (!_isNow) return NubiaCard(child: content);

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: NubiaColors.n300),
        boxShadow: [
          BoxShadow(
            color: NubiaColors.n900.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: content,
    );
  }
}

/// Ligne `.dt` (icône + texte) — date ou échéance de la phase (#5298).
/// Maquette : `design/v2-screens/patient-mon-plan-de-soins.png`.
class _PhaseDateRow extends StatelessWidget {
  const _PhaseDateRow({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.calendar_today_outlined,
            size: 14, color: NubiaColors.n500),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontSize: 12, color: NubiaColors.n500),
          ),
        ),
      ],
    );
  }
}

/// Bloc `.amt` — montant de la phase avec un libellé qui dit honnêtement son
/// statut de paiement : réglé, couvert par un devis signé, ou estimation
/// (#5298). Maquette : `design/v2-screens/patient-mon-plan-de-soins.png`.
class _PhaseAmountRow extends StatelessWidget {
  const _PhaseAmountRow({required this.phase});

  final PatientTreatmentPlanPhase phase;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: Key('phase_${phase.id}_amount_row'),
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.only(top: 12),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: NubiaColors.n100)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            _phaseCoverageLabels[phase.coverage]!,
            style: const TextStyle(fontSize: 13, color: NubiaColors.n500),
          ),
          Text(
            formatTreatmentPlanCents(phase.amountCents),
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: NubiaColors.n900,
              fontFeatures: tabularFigures,
            ),
          ),
        ],
      ),
    );
  }
}

/// Bandeau warning « devis en attente » sur la carte d'une phase à venir
/// bloquée par un devis non signé (#5300). Maquette :
/// `design/v2-screens/patient-mon-plan-de-soins.png`.
class _PendingQuoteBanner extends StatelessWidget {
  const _PendingQuoteBanner({super.key, required this.sentAt});

  final DateTime? sentAt;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    final sentAtLabel =
        sentAt != null ? formatTreatmentPlanDayMonth(sentAt!.toLocal()) : null;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tokens.warningBg,
        border: Border.all(color: NubiaColors.warningBorder),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.description, size: 18, color: tokens.warningFg),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: const TextStyle(fontSize: 12, color: Color(0xFF78350F)),
                children: [
                  TextSpan(
                    text: sentAtLabel != null
                        ? 'Un devis vous a été envoyé le $sentAtLabel.'
                        : 'Un devis vous a été envoyé.',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const TextSpan(
                    text: ' Cette étape ne peut pas être programmée avant '
                        'votre accord.',
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

/// Rappelle que les montants en attente sont estimatifs et renvoie au devis
/// pour le reste à charge définitif (transparence, #5302).
class _EstimatedAmountsNotice extends StatelessWidget {
  const _EstimatedAmountsNotice();

  @override
  Widget build(BuildContext context) {
    return NubiaCard(
      key: const Key('treatment_plan_estimated_amounts_notice'),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info, size: 20, color: NubiaColors.n400),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Les montants en attente sont des estimations de votre '
              'praticien. Le reste à votre charge définitif figure sur le '
              'devis, après calcul des remboursements de l\'Assurance '
              'Maladie et de votre mutuelle.',
              style: TextStyle(fontSize: 11.5, color: NubiaColors.n500),
            ),
          ),
        ],
      ),
    );
  }
}

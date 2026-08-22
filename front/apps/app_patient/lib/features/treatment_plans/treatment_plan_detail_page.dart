import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'treatment_plans_bloc.dart';
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
    final totalCents = plan.totalCostCents;
    final remainingCents = plan.remainingCents;

    return SingleChildScrollView(
      key: const Key('treatment_plan_detail_loaded'),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(plan.title, style: textTheme.titleLarge),
          const SizedBox(height: 16),
          if (totalCents != null)
            AmountHeader(
              label: 'Total du plan de soins',
              amount: formatTreatmentPlanCents(totalCents),
              remainingLabel: remainingCents != null ? 'Reste à charge' : null,
              remainingAmount: remainingCents != null
                  ? formatTreatmentPlanCents(remainingCents)
                  : null,
            ),
          const SizedBox(height: 24),
          Text('Phases', style: textTheme.titleMedium),
          const SizedBox(height: 12),
          if (plan.phases.isEmpty)
            const NubiaEmptyState(
              key: Key('treatment_plan_phases_empty'),
              icon: Icons.timeline_outlined,
              title: 'Aucune phase pour le moment',
            )
          else
            for (final phase in plan.phases)
              Padding(
                key: Key('treatment_plan_phase_${phase.id}'),
                padding: const EdgeInsets.only(bottom: 12),
                child: NubiaCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child:
                                Text(phase.title, style: textTheme.titleSmall),
                          ),
                          StatusPill(
                            label: _phaseStatusLabels[phase.status] ??
                                phase.status,
                            variant: _phaseStatusVariants[phase.status] ??
                                StatusPillVariant.info,
                          ),
                        ],
                      ),
                      if (phase.items.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        for (final item in phase.items)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(child: Text(item.label)),
                                Text(formatTreatmentPlanCents(
                                    item.unitAmountCents)),
                              ],
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
              ),
          const SizedBox(height: 16),
          const _EstimatedAmountsNotice(),
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

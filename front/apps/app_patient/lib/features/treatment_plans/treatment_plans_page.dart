import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

import 'treatment_plans_bloc.dart';

/// Liste des plans de traitement du patient (#4261).
class PatientTreatmentPlansPage extends StatelessWidget {
  const PatientTreatmentPlansPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<PatientTreatmentPlansBloc>(
      create: (_) => GetIt.instance<PatientTreatmentPlansBloc>()
        ..add(const PatientTreatmentPlansRequested()),
      child: const PatientTreatmentPlansBody(),
    );
  }
}

/// Corps de l'écran — public pour les tests widget.
class PatientTreatmentPlansBody extends StatelessWidget {
  const PatientTreatmentPlansBody({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mes plans de traitement')),
      body: BlocBuilder<PatientTreatmentPlansBloc, PatientTreatmentPlansState>(
        builder: (context, state) {
          switch (state) {
            case PatientTreatmentPlansLoading():
              return const _TreatmentPlansSkeleton();
            case PatientTreatmentPlansError(:final message):
              return NubiaErrorWidget(
                message: message,
                onRetry: () => context
                    .read<PatientTreatmentPlansBloc>()
                    .add(const PatientTreatmentPlansRequested()),
              );
            case PatientTreatmentPlansLoaded(:final plans):
              if (plans.isEmpty) {
                return const NubiaEmptyState(
                  key: Key('treatment_plans_empty'),
                  icon: Icons.medical_information_outlined,
                  title: 'Aucun plan de traitement',
                  subtitle: 'Votre praticien n\'a pas encore proposé de plan '
                      'de traitement.',
                );
              }
              return ListView.builder(
                key: const Key('treatment_plans_loaded'),
                itemCount: plans.length,
                itemBuilder: (context, index) {
                  final plan = plans[index];
                  return ListRow(
                    key: Key('treatment_plan_${plan.id}'),
                    title: plan.title,
                    trailing: StatusPill(
                      label: treatmentPlanStatusLabels[plan.status] ??
                          plan.status,
                      variant: treatmentPlanStatusVariants[plan.status] ??
                          StatusPillVariant.info,
                    ),
                    onTap: () => context.push('/treatment-plans/${plan.id}'),
                  );
                },
              );
          }
        },
      ),
    );
  }
}

/// Squelette de chargement — quelques cartes placeholder empilées, sur le
/// modèle du coffre-fort documentaire (`_DocumentsSkeleton`).
class _TreatmentPlansSkeleton extends StatelessWidget {
  const _TreatmentPlansSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: const Key('treatment_plans_loading'),
      padding: const EdgeInsets.all(16),
      children: const [
        _TreatmentPlanSkeletonCard(),
        SizedBox(height: 12),
        _TreatmentPlanSkeletonCard(),
        SizedBox(height: 12),
        _TreatmentPlanSkeletonCard(),
      ],
    );
  }
}

class _TreatmentPlanSkeletonCard extends StatelessWidget {
  const _TreatmentPlanSkeletonCard();

  @override
  Widget build(BuildContext context) {
    return const NubiaCard(
      child: Row(
        children: [
          Expanded(
            child: NubiaSkeletonLoader(height: 16, width: 180),
          ),
          SizedBox(width: 12),
          NubiaSkeletonLoader(height: 22, width: 72, borderRadius: 999),
        ],
      ),
    );
  }
}

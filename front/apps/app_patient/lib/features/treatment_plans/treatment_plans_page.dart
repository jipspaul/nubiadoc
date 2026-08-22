import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

import 'treatment_plans_bloc.dart';
import 'widgets/pending_quote_card.dart';

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
              final pendingQuotePlans =
                  plans.where((plan) => plan.pendingQuoteId != null).toList();
              final otherPlans =
                  plans.where((plan) => plan.pendingQuoteId == null).toList();
              final items = <Widget>[
                if (pendingQuotePlans.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: _PendingQuoteSectionHeader(
                      count: pendingQuotePlans.length,
                    ),
                  ),
                  for (final plan in pendingQuotePlans)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: PendingQuoteCard(
                        key: Key('pending_quote_card_${plan.id}'),
                        plan: plan,
                      ),
                    ),
                ],
                for (final plan in otherPlans)
                  ListRow(
                    key: Key('treatment_plan_${plan.id}'),
                    title: plan.title,
                    trailing: StatusPill(
                      label: treatmentPlanStatusLabels[plan.status] ??
                          plan.status,
                      variant: treatmentPlanStatusVariants[plan.status] ??
                          StatusPillVariant.info,
                    ),
                    onTap: () => context.push('/treatment-plans/${plan.id}'),
                  ),
                const _TreatmentPlansInfoNotice(),
              ];
              return ListView.builder(
                key: const Key('treatment_plans_loaded'),
                itemCount: items.length,
                itemBuilder: (context, index) => items[index],
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

/// En-tête de la section « À votre décision » — regroupe les plans dont un
/// devis est reçu et non signé, sortis du flux normal pour porter leur
/// propre carte warning (#5291). Maquette :
/// `design/v2-screens/patient-mon-plan-de-soins.png`.
class _PendingQuoteSectionHeader extends StatelessWidget {
  const _PendingQuoteSectionHeader({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    final textTheme = Theme.of(context).textTheme;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          'À VOTRE DÉCISION',
          style: textTheme.labelSmall?.copyWith(
            color: tokens.textTertiary,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.4,
          ),
        ),
        Text(
          '$count devis en attente',
          style: TextStyle(fontSize: 11.5, color: tokens.textTertiary),
        ),
      ],
    );
  }
}

/// Encart de bas de liste rappelant ce qu'est un plan de soins et le
/// caractère indicatif des montants (design de transparence, #5292).
class _TreatmentPlansInfoNotice extends StatelessWidget {
  const _TreatmentPlansInfoNotice();

  @override
  Widget build(BuildContext context) {
    return NubiaCard(
      key: const Key('treatment_plans_info_notice'),
      padding: const EdgeInsets.all(12),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.shield, size: 20, color: NubiaColors.n400),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Un plan de soins décrit les étapes proposées par votre '
              "praticien. Les montants sont indicatifs tant qu'un devis n'a "
              'pas été signé.',
              style: TextStyle(fontSize: 11.5, color: NubiaColors.n500),
            ),
          ),
        ],
      ),
    );
  }
}

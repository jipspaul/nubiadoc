import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

import 'treatment_plans_bloc.dart';
import 'widgets/pending_quote_card.dart';
import 'widgets/plan_card.dart';

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
              final inProgressPlans = plans
                  .where((plan) =>
                      plan.pendingQuoteId == null &&
                      (plan.status == 'in_progress' ||
                          plan.status == 'accepted'))
                  .toList();
              final donePlans = plans
                  .where((plan) =>
                      plan.pendingQuoteId == null && plan.status == 'done')
                  .toList();
              final items = <Widget>[
                if (inProgressPlans.isNotEmpty) ...[
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: _SectionHeader(title: 'EN COURS'),
                  ),
                  for (final plan in inProgressPlans) PlanCard(plan: plan),
                ],
                if (pendingQuotePlans.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: _SectionHeader(
                      title: 'À VOTRE DÉCISION',
                      trailing: '${pendingQuotePlans.length} devis en attente',
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
                if (donePlans.isNotEmpty) ...[
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: _SectionHeader(title: 'TERMINÉS'),
                  ),
                  for (final plan in donePlans) PlanCard(plan: plan),
                ],
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

/// En-tête de section `.gh` (« En cours » / « À votre décision » /
/// « Terminés ») groupant la liste plate des plans (#5290). Maquette :
/// `design/v2-screens/patient-mon-plan-de-soins.png`.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.trailing});

  final String title;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(
      fontSize: 11.5,
      fontWeight: FontWeight.w600,
      color: NubiaColors.n400,
    );

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title, style: style),
        if (trailing != null) Text(trailing!, style: style),
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

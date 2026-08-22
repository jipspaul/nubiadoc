import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import '../../router/app_router.dart';
import 'treatment_plans_bloc.dart';
import 'widgets/pending_quote_card.dart';
import 'widgets/treatment_plan_format_utils.dart';

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
                  for (final plan in inProgressPlans) _PlanCard(plan: plan),
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
                  for (final plan in donePlans) _PlanRow(plan: plan),
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

/// Ligne d'un plan hors section « À votre décision » (statut + navigation
/// vers le détail).
class _PlanRow extends StatelessWidget {
  const _PlanRow({required this.plan});

  final PatientTreatmentPlan plan;

  @override
  Widget build(BuildContext context) {
    return ListRow(
      key: Key('treatment_plan_${plan.id}'),
      title: plan.title,
      trailing: StatusPill(
        label: treatmentPlanStatusLabels[plan.status] ?? plan.status,
        variant: treatmentPlanStatusVariants[plan.status] ??
            StatusPillVariant.info,
      ),
      onTap: () => context.push('/treatment-plans/${plan.id}'),
    );
  }
}

/// Carte d'un plan « En cours » (voir ticket carte riche #5288 pour son
/// contenu final) — pour l'instant reprend `_PlanRow` (titre + pastille de
/// statut) et y ajoute, en pied, la rangée « Prochaine séance » quand une
/// séance est programmée pour l'étape courante du plan (#5289). Maquette :
/// `design/v2-screens/patient-mon-plan-de-soins.png`.
class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.plan});

  final PatientTreatmentPlan plan;

  @override
  Widget build(BuildContext context) {
    final nextAppointmentAt = plan.nextAppointmentAt;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: NubiaCard(
        key: Key('treatment_plan_${plan.id}'),
        state: NubiaCardState.interactive,
        onTap: () => context.push('/treatment-plans/${plan.id}'),
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    plan.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                const SizedBox(width: 12),
                StatusPill(
                  label: treatmentPlanStatusLabels[plan.status] ?? plan.status,
                  variant: treatmentPlanStatusVariants[plan.status] ??
                      StatusPillVariant.info,
                ),
              ],
            ),
            if (nextAppointmentAt != null)
              _NextAppointmentRow(plan: plan, appointmentAt: nextAppointmentAt),
          ],
        ),
      ),
    );
  }
}

/// Rangée `.nx` en pied de carte — icône + « Prochaine séance » (jour/heure
/// en gras) + lien « Voir » qui ouvre le rendez-vous, indépendamment du tap
/// global de la carte vers le détail du plan (#5289).
class _NextAppointmentRow extends StatelessWidget {
  const _NextAppointmentRow({required this.plan, required this.appointmentAt});

  final PatientTreatmentPlan plan;
  final DateTime appointmentAt;

  @override
  Widget build(BuildContext context) {
    final local = appointmentAt.toLocal();
    final label = '${formatTreatmentPlanWeekdayDayMonth(local)}, '
        '${formatTreatmentPlanTime(local)}';

    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.only(top: 10),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: NubiaColors.n100)),
      ),
      child: Row(
        children: [
          const Icon(Icons.event, size: 16, color: NubiaColors.brand700),
          const SizedBox(width: 6),
          Expanded(
            child: Text.rich(
              key: Key('treatment_plan_${plan.id}_next_appointment_label'),
              TextSpan(
                style: const TextStyle(fontSize: 12.5, color: NubiaColors.n600),
                children: [
                  const TextSpan(text: 'Prochaine séance '),
                  TextSpan(
                    text: label,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ),
          GestureDetector(
            key: Key('treatment_plan_${plan.id}_next_appointment_cta'),
            onTap: () =>
                context.push('${AppRouter.mesRdv}?id=${plan.nextAppointmentId}'),
            child: const Text(
              'Voir',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: NubiaColors.brand700,
              ),
            ),
          ),
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

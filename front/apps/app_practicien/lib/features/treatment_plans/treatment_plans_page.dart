//! Écran plans de traitement (#4051) — liste les plans d'un patient, permet
//! d'en créer un et d'y ajouter des phases.

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'treatment_plans_cubit.dart';

class TreatmentPlansPage extends StatelessWidget {
  const TreatmentPlansPage({super.key, required this.patientId});

  final String patientId;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => TreatmentPlansCubit(
        patientId: patientId,
        listPlans: GetIt.instance<ListTreatmentPlansUseCase>(),
        createPlan: GetIt.instance<CreateTreatmentPlanUseCase>(),
        createPhase: GetIt.instance<CreateTreatmentPhaseUseCase>(),
      ),
      child: const _TreatmentPlansBody(),
    );
  }
}

class _TreatmentPlansBody extends StatelessWidget {
  const _TreatmentPlansBody();

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<TreatmentPlansCubit, TreatmentPlansState>(
      listenWhen: (prev, curr) =>
          curr is TreatmentPlansLoaded &&
          curr.actionError != null &&
          (prev is! TreatmentPlansLoaded ||
              prev.actionError != curr.actionError),
      listener: (context, state) {
        if (state is TreatmentPlansLoaded && state.actionError != null) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(state.actionError!)));
        }
      },
      builder: (context, state) {
        return Scaffold(
          appBar: AppBar(title: const Text('Plans de traitement')),
          floatingActionButton: state is TreatmentPlansLoaded
              ? FloatingActionButton(
                  key: const Key('treatment_plans_new_plan_fab'),
                  onPressed: () => _promptNewPlan(context),
                  child: const Icon(Icons.add),
                )
              : null,
          body: switch (state) {
            TreatmentPlansLoading() => const Center(
                key: Key('treatment_plans_loading'),
                child: CircularProgressIndicator(),
              ),
            TreatmentPlansError(:final message) => NubiaErrorWidget(
                key: const Key('treatment_plans_error'),
                message: message,
                onRetry: () => context.read<TreatmentPlansCubit>().load(),
              ),
            TreatmentPlansLoaded(:final plans, :final busy) =>
              _PlansList(plans: plans, busy: busy),
          },
        );
      },
    );
  }

  Future<void> _promptNewPlan(BuildContext context) async {
    final cubit = context.read<TreatmentPlansCubit>();
    final title = await showDialog<String>(
      context: context,
      builder: (_) => const _TitlePromptDialog(
        dialogKey: Key('treatment_plan_create_dialog'),
        fieldKey: Key('treatment_plan_title_field'),
        submitKey: Key('treatment_plan_create_submit'),
        dialogTitle: 'Nouveau plan de traitement',
        fieldLabel: 'Titre du plan',
      ),
    );
    if (title != null && title.isNotEmpty) {
      await cubit.createPlan(title);
    }
  }
}

class _PlansList extends StatelessWidget {
  const _PlansList({required this.plans, required this.busy});

  final List<TreatmentPlan> plans;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    if (plans.isEmpty) {
      return const NubiaEmptyState(
        key: Key('treatment_plans_empty'),
        icon: Icons.assignment_outlined,
        title: 'Aucun plan de traitement',
        subtitle: 'Créez le premier plan avec le bouton +.',
      );
    }
    return ListView.builder(
      key: const Key('treatment_plans_list'),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      itemCount: plans.length,
      itemBuilder: (context, i) => _PlanCard(plan: plans[i], busy: busy),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.plan, required this.busy});

  final TreatmentPlan plan;
  final bool busy;

  Future<void> _promptNewPhase(BuildContext context) async {
    final cubit = context.read<TreatmentPlansCubit>();
    final title = await showDialog<String>(
      context: context,
      builder: (_) => _TitlePromptDialog(
        dialogKey: Key('treatment_phase_create_dialog_${plan.id}'),
        fieldKey: Key('treatment_phase_title_field_${plan.id}'),
        submitKey: Key('treatment_phase_create_submit_${plan.id}'),
        dialogTitle: 'Nouvelle phase',
        fieldLabel: 'Titre de la phase',
      ),
    );
    if (title != null && title.isNotEmpty) {
      final nextPosition = plan.phases.isEmpty
          ? 1
          : plan.phases.map((p) => p.position).reduce((a, b) => a > b ? a : b) +
              1;
      await cubit.createPhase(plan.id, title, nextPosition);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Card(
      key: Key('treatment_plan_${plan.id}'),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(plan.title, style: textTheme.titleMedium),
                ),
                Text(
                  plan.status,
                  style: textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (plan.phases.isEmpty)
              Text(
                'Aucune phase.',
                style: textTheme.bodySmall,
                key: Key('treatment_plan_no_phases_${plan.id}'),
              )
            else
              for (final phase in plan.phases)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    key: Key('treatment_phase_${phase.id}'),
                    children: [
                      Text('${phase.position}. ', style: textTheme.bodyMedium),
                      Expanded(
                        child: Text(phase.title, style: textTheme.bodyMedium),
                      ),
                      Text(phase.status, style: textTheme.bodySmall),
                    ],
                  ),
                ),
            const SizedBox(height: 8),
            NubiaButton(
              key: Key('treatment_plan_add_phase_${plan.id}'),
              variant: NubiaButtonVariant.secondary,
              size: NubiaButtonSize.sm,
              icon: Icons.add,
              label: 'Ajouter une phase',
              onPressed: busy ? null : () => _promptNewPhase(context),
            ),
          ],
        ),
      ),
    );
  }
}

/// Dialogue générique « saisir un titre » — réutilisé pour la création de
/// plan et de phase (même forme, un seul champ texte).
class _TitlePromptDialog extends StatefulWidget {
  const _TitlePromptDialog({
    required this.dialogKey,
    required this.fieldKey,
    required this.submitKey,
    required this.dialogTitle,
    required this.fieldLabel,
  });

  final Key dialogKey;
  final Key fieldKey;
  final Key submitKey;
  final String dialogTitle;
  final String fieldLabel;

  @override
  State<_TitlePromptDialog> createState() => _TitlePromptDialogState();
}

class _TitlePromptDialogState extends State<_TitlePromptDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: widget.dialogKey,
      title: Text(widget.dialogTitle),
      content: NubiaTextField(
        key: widget.fieldKey,
        variant: NubiaTextFieldVariant.outlined,
        controller: _controller,
        label: widget.fieldLabel,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        NubiaButton(
          key: widget.submitKey,
          size: NubiaButtonSize.sm,
          icon: Icons.check,
          label: 'Créer',
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
        ),
      ],
    );
  }
}

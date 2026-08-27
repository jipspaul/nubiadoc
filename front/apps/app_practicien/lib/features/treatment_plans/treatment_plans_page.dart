//! Écran plans de traitement (#4051) — liste les plans d'un patient, permet
//! d'en créer un et d'y ajouter des phases.

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import '../consultation_clinique/ccam_picker.dart';
import 'patient_header_cubit.dart';
import 'treatment_plans_cubit.dart';
import 'widgets/patient_header_bar.dart';

class TreatmentPlansPage extends StatelessWidget {
  const TreatmentPlansPage({super.key, required this.patientId});

  final String patientId;

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (_) => TreatmentPlansCubit(
            patientId: patientId,
            listPlans: GetIt.instance<ListTreatmentPlansUseCase>(),
            createPlan: GetIt.instance<CreateTreatmentPlanUseCase>(),
            createPhase: GetIt.instance<CreateTreatmentPhaseUseCase>(),
          ),
        ),
        BlocProvider(
          create: (_) => PatientHeaderCubit(
            patientId: patientId,
            getPatient: GetIt.instance<GetCabinetPatientUseCase>(),
          ),
        ),
      ],
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
          floatingActionButton: state is TreatmentPlansLoaded
              ? FloatingActionButton(
                  key: const Key('treatment_plans_new_plan_fab'),
                  tooltip: 'Nouveau plan de traitement',
                  onPressed: () => _promptNewPlan(context),
                  child: const Icon(Icons.add),
                )
              : null,
          body: Column(
            children: [
              const PatientHeaderBar(trailingLabel: 'Plans de traitement'),
              Expanded(
                child: switch (state) {
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
              ),
            ],
          ),
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

  /// Ouvre la sélection d'acte CCAM (réutilise [CcamPicker], #5023). Aucun
  /// cas d'usage back « ajouter un acte à une phase » n'existe encore
  /// (dépend des tickets domaine « actes » / « rendu des actes ») : la
  /// sélection ferme simplement le dialogue pour l'instant, sans persister
  /// l'acte sur la phase.
  Future<void> _openAddAct(BuildContext context, TreatmentPhase phase) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        key: Key('treatment_phase_add_act_dialog_${phase.id}'),
        child: SizedBox(
          width: 420,
          child: CcamPicker(
            key: Key('treatment_phase_ccam_picker_${phase.id}'),
            useCase: GetIt.instance<GetActsUseCase>(),
            favoritesUseCase: GetIt.instance<FavoriteActsUseCase>(),
            onActSubmitted: ({
              required String code,
              required String label,
              String? tooth,
              required int amountCents,
            }) =>
                Navigator.of(dialogContext).pop(),
          ),
        ),
      ),
    );
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
                StatusPill(
                  label: treatmentPlanStatusLabels[plan.status] ??
                      plan.status,
                  variant: treatmentPlanStatusVariants[plan.status] ??
                      StatusPillVariant.info,
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
              for (final phase in plan.phases) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    key: Key('treatment_phase_${phase.id}'),
                    children: [
                      Text('${phase.position}. ', style: textTheme.bodyMedium),
                      Expanded(
                        child: Text(phase.title, style: textTheme.bodyMedium),
                      ),
                      StatusPill(
                        label: treatmentPlanStatusLabels[phase.status] ??
                            phase.status,
                        variant: treatmentPlanStatusVariants[phase.status] ??
                            StatusPillVariant.info,
                      ),
                    ],
                  ),
                ),
                // Phase active (#5023) : affordance d'ajout d'acte sous la
                // liste des actes de la phase. Le rendu des actes eux-mêmes
                // (ticket dédié « rendu des actes ») n'existe pas encore, donc
                // l'affordance suit directement la ligne de la phase.
                if (phase.status == 'in_progress')
                  _AddActAffordance(
                    key: Key('treatment_phase_add_act_${phase.id}'),
                    buttonKey: Key('treatment_phase_add_act_button_${phase.id}'),
                    onTap: busy ? null : () => _openAddAct(context, phase),
                  ),
              ],
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

/// Affordance « Ajouter un acte à cette phase » (#5023, maquette design-v2
/// `.addact`) : séparateur pointillé, icône `add`, libellé gris `n500`.
/// Affichée sous la liste des actes de la phase active (`in_progress`).
class _AddActAffordance extends StatelessWidget {
  const _AddActAffordance({
    super.key,
    required this.buttonKey,
    required this.onTap,
  });

  final Key buttonKey;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 1,
            child: CustomPaint(
              painter: _DashedLinePainter(color: tokens.borderDefault),
            ),
          ),
          Material(
            color: Colors.transparent,
            child: InkWell(
              key: buttonKey,
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    const Icon(Icons.add, size: 18, color: NubiaColors.n500),
                    const SizedBox(width: 6),
                    Text(
                      'Ajouter un acte à cette phase',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: NubiaColors.n500),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Ligne horizontale pointillée — Flutter n'a pas de `BorderStyle.dashed`
/// natif (maquette design-v2, séparateur `.addact`, #5023).
class _DashedLinePainter extends CustomPainter {
  _DashedLinePainter({required this.color});

  final Color color;

  static const _dashWidth = 4.0;
  static const _dashSpace = 3.0;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    var x = 0.0;
    while (x < size.width) {
      canvas.drawLine(Offset(x, 0), Offset(x + _dashWidth, 0), paint);
      x += _dashWidth + _dashSpace;
    }
  }

  @override
  bool shouldRepaint(covariant _DashedLinePainter oldDelegate) =>
      oldDelegate.color != color;
}

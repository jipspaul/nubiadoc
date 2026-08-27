//! Écran plans de traitement (#4051) — liste les plans d'un patient, permet
//! d'en créer un et d'y ajouter des phases.

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import '../../router/app_router.dart';
import '../consultation_clinique/ccam_picker.dart';
import 'patient_header_cubit.dart';
import 'treatment_plans_cubit.dart';
import 'widgets/patient_header_bar.dart';
import 'widgets/phase_quote_banner.dart';
import 'widgets/phase_timeline.dart';
import 'widgets/plan_footer.dart';
import 'widgets/plan_kpi_row.dart';

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

class _PlanCard extends StatefulWidget {
  const _PlanCard({required this.plan, required this.busy});

  final TreatmentPlan plan;
  final bool busy;

  @override
  State<_PlanCard> createState() => _PlanCardState();
}

class _PlanCardState extends State<_PlanCard> {
  final _newPhaseTitleController = TextEditingController();
  bool _composingPhase = false;

  @override
  void dispose() {
    _newPhaseTitleController.dispose();
    super.dispose();
  }

  Future<void> _submitNewPhase(BuildContext context) async {
    final title = _newPhaseTitleController.text.trim();
    if (title.isEmpty) return;
    final plan = widget.plan;
    final nextPosition = plan.phases.isEmpty
        ? 1
        : plan.phases.map((p) => p.position).reduce((a, b) => a > b ? a : b) +
            1;
    await context.read<TreatmentPlansCubit>().createPhase(
          plan.id,
          title,
          nextPosition,
        );
  }

  /// Ouvre le dialogue de renommage (réutilise [_TitlePromptDialog],
  /// pré-rempli avec le titre courant). Aucun cas d'usage back « renommer un
  /// plan de traitement » n'existe encore (seule la création, `POST
  /// /v1/cabinet/treatment-plans`, est exposée côté API) : le dialogue ferme
  /// simplement sans persister pour l'instant.
  Future<void> _promptRename(BuildContext context) async {
    final plan = widget.plan;
    await showDialog<String>(
      context: context,
      builder: (_) => _TitlePromptDialog(
        dialogKey: Key('treatment_plan_rename_dialog_${plan.id}'),
        fieldKey: Key('treatment_plan_rename_field_${plan.id}'),
        submitKey: Key('treatment_plan_rename_submit_${plan.id}'),
        dialogTitle: 'Renommer le plan',
        fieldLabel: 'Titre du plan',
        initialValue: plan.title,
        submitLabel: 'Renommer',
      ),
    );
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
    final plan = widget.plan;
    final busy = widget.busy;
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
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        plan.title,
                        style: textTheme.titleMedium,
                        overflow: TextOverflow.ellipsis,
                      ),
                      StatusPill(
                        label: treatmentPlanStatusLabels[plan.status] ??
                            plan.status,
                        variant: treatmentPlanStatusVariants[plan.status] ??
                            StatusPillVariant.info,
                      ),
                      StatusPill(
                        key: Key('treatment_plan_created_at_${plan.id}'),
                        label: 'Créé le ${_formatPlanDate(plan.createdAt)}',
                        variant: StatusPillVariant.neutral,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                NubiaButton(
                  key: Key('treatment_plan_rename_${plan.id}'),
                  variant: NubiaButtonVariant.secondary,
                  size: NubiaButtonSize.sm,
                  icon: Icons.edit,
                  label: 'Renommer',
                  onPressed: busy ? null : () => _promptRename(context),
                ),
                const SizedBox(width: 8),
                NubiaButton(
                  key: Key('treatment_plan_generate_quote_${plan.id}'),
                  size: NubiaButtonSize.sm,
                  icon: Icons.description,
                  label: 'Générer le devis',
                  onPressed: busy ? null : () => context.push(AppRouter.devis),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Agrégats à 0 tant que le ticket domaine « agrégats de
            // montants » (#5013) n'a pas doté TreatmentPlan de montants
            // réels (même limitation que PlanFooter ci-dessous).
            PlanKpiRow(
              key: Key('treatment_plan_kpis_${plan.id}'),
              totalCents: 0,
              signedCents: 0,
              remainingToQuoteCents: 0,
            ),
            const SizedBox(height: 16),
            if (plan.phases.isEmpty)
              Text(
                'Aucune phase.',
                style: textTheme.bodySmall,
                key: Key('treatment_plan_no_phases_${plan.id}'),
              )
            else
              PhaseTimeline(
                children: [
                  for (final (index, phase) in plan.phases.indexed)
                    PhaseStep(
                      status: phase.status,
                      number: phase.position,
                      isLast: index == plan.phases.length - 1,
                      card: _PhaseCard(
                        key: Key('treatment_phase_${phase.id}'),
                        phase: phase,
                        busy: busy,
                        // Agrégat à 0 tant que le ticket domaine « agrégats
                        // de montants » (#5013) n'a pas doté TreatmentPhase
                        // d'un montant réel (même limitation que PlanKpiRow
                        // et PlanFooter ci-dessus).
                        amountCents: 0,
                        onAddAct: () => _openAddAct(context, phase),
                        onOpenQuote: () => context.push(AppRouter.devis),
                        onGenerateQuote: () => context.push(AppRouter.devis),
                      ),
                    ),
                ],
              ),
            const SizedBox(height: 8),
            if (_composingPhase)
              _NewPhaseComposer(
                fieldKey: Key('treatment_phase_title_field_${plan.id}'),
                submitKey: Key('treatment_phase_create_submit_${plan.id}'),
                controller: _newPhaseTitleController,
                busy: busy,
                onSubmit: () => _submitNewPhase(context),
                onCancel: () => setState(() => _composingPhase = false),
              )
            else
              _NewPhaseEntry(
                key: Key('treatment_plan_add_phase_${plan.id}'),
                onTap:
                    busy ? null : () => setState(() => _composingPhase = true),
              ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.only(top: 12),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: NubiaColors.n200)),
              ),
              // Agrégats à 0 tant que le ticket domaine « agrégats de
              // montants » (#5013) n'a pas doté TreatmentPlan/TreatmentPhase
              // de montants réels.
              child: PlanFooter(
                key: Key('plan_footer_${plan.id}'),
                warningKey: Key('plan_footer_warning_${plan.id}'),
                realizedCents: 0,
                engagedCents: 0,
                remainingToQuoteCents: 0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Carte `.bd` d'une phase (#5021, maquette design-v2 `.ph`) — en-tête
/// (titre + statut) et, pour la phase active, l'affordance d'ajout d'acte
/// sous la carte. Affichée à droite du rail vertical par [PhaseTimeline].
class _PhaseCard extends StatelessWidget {
  const _PhaseCard({
    super.key,
    required this.phase,
    required this.busy,
    required this.amountCents,
    required this.onAddAct,
    required this.onOpenQuote,
    required this.onGenerateQuote,
  });

  final TreatmentPhase phase;
  final bool busy;
  final int amountCents;
  final VoidCallback onAddAct;
  final VoidCallback onOpenQuote;
  final VoidCallback onGenerateQuote;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return NubiaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(phase.title, style: textTheme.bodyMedium),
              ),
              StatusPill(
                label: treatmentPlanStatusLabels[phase.status] ?? phase.status,
                variant: treatmentPlanStatusVariants[phase.status] ??
                    StatusPillVariant.info,
              ),
              const SizedBox(width: 8),
              Text(
                NubiaMoney.formatCents(amountCents),
                key: Key('treatment_phase_amount_${phase.id}'),
                style: textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontFeatures: tabularFigures,
                ),
              ),
            ],
          ),
          // Phase active (#5023) : affordance d'ajout d'acte sous la
          // liste des actes de la phase. Le rendu des actes eux-mêmes
          // (ticket dédié « rendu des actes ») n'existe pas encore, donc
          // l'affordance suit directement l'en-tête de la carte.
          if (phase.status == 'in_progress')
            _AddActAffordance(
              key: Key('treatment_phase_add_act_${phase.id}'),
              buttonKey: Key('treatment_phase_add_act_button_${phase.id}'),
              onTap: busy ? null : onAddAct,
            ),
          // Bandeau devis (#5019, maquette design-v2 point 3). Aucune
          // référence de devis par phase n'existe encore côté domaine/API
          // (ticket domaine « référence de devis par phase », pas livré :
          // `TreatmentPhase` ne porte aucun champ devis pour l'instant) —
          // état absence pour toutes les phases en attendant. « Ouvrir »/
          // « Générer » redirigent vers la liste des devis (`/devis`), en
          // l'absence de route dédiée par devis/phase.
          PhaseQuoteBanner(
            key: Key('treatment_phase_quote_${phase.id}'),
            openKey: Key('treatment_phase_quote_open_${phase.id}'),
            generateKey: Key('treatment_phase_quote_generate_${phase.id}'),
            quoteNumber: null,
            signedAtLabel: null,
            depositPaid: false,
            onOpen: onOpenQuote,
            onGenerate: onGenerateQuote,
          ),
        ],
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
    this.initialValue,
    this.submitLabel = 'Créer',
  });

  final Key dialogKey;
  final Key fieldKey;
  final Key submitKey;
  final String dialogTitle;
  final String fieldLabel;
  final String? initialValue;
  final String submitLabel;

  @override
  State<_TitlePromptDialog> createState() => _TitlePromptDialogState();
}

class _TitlePromptDialogState extends State<_TitlePromptDialog> {
  late final _controller = TextEditingController(text: widget.initialValue);

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
          label: widget.submitLabel,
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
        ),
      ],
    );
  }
}

/// Entrée « Ajouter une phase » (maquette design-v2 `.newph`) : séparateur
/// pointillé, icône `add`, libellé gris `n500`, au bas de la chronologie des
/// phases. Composition en place au tap (#5022) — plus d'`AlertDialog`.
class _NewPhaseEntry extends StatelessWidget {
  const _NewPhaseEntry({super.key, required this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    return Column(
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
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.add, size: 18, color: NubiaColors.n500),
                  const SizedBox(width: 6),
                  Text(
                    'Ajouter une phase',
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
    );
  }
}

/// Composition en place d'une nouvelle phase (#5022, maquette design-v2
/// `.newph`) : remplace [_NewPhaseEntry] au tap — champ de titre + validation,
/// sans quitter le contexte du plan (pas d'`AlertDialog`).
class _NewPhaseComposer extends StatelessWidget {
  const _NewPhaseComposer({
    required this.fieldKey,
    required this.submitKey,
    required this.controller,
    required this.busy,
    required this.onSubmit,
    required this.onCancel,
  });

  final Key fieldKey;
  final Key submitKey;
  final TextEditingController controller;
  final bool busy;
  final VoidCallback onSubmit;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: NubiaTextField(
            key: fieldKey,
            variant: NubiaTextFieldVariant.outlined,
            controller: controller,
            label: 'Titre de la phase',
            enabled: !busy,
            onSubmitted: busy ? null : (_) => onSubmit(),
          ),
        ),
        const SizedBox(width: 8),
        NubiaButton(
          key: submitKey,
          size: NubiaButtonSize.sm,
          icon: Icons.check,
          label: 'Créer',
          onPressed: busy ? null : onSubmit,
        ),
        const SizedBox(width: 4),
        NubiaButton(
          variant: NubiaButtonVariant.tertiary,
          size: NubiaButtonSize.sm,
          label: 'Annuler',
          onPressed: busy ? null : onCancel,
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

/// Formate une date « DD/MM/YYYY » (pill « Créé le », maquette design-v2
/// `.mut`, #5017).
String _formatPlanDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

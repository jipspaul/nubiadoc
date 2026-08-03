import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import '../consultation_clinique_bloc.dart';
import '../consultation_clinique_event.dart';
import '../consultation_clinique_state.dart';
import '../modules/dentaire/odontogram_panel.dart';
import '../modules/dentaire/tooth_act_suggestions.dart';
import '../modules/dentaire/tooth_status_update_dialog.dart';
import '../modules/dentaire/treated_tooth_tile.dart';
import '../sterilization_scan_page.dart';
import '../../dental_chart/dental_chart_cubit.dart';
import 'act_entry_panel.dart';
import 'clinical_context_panel.dart';
import 'next_step_panel.dart';
import 'patient_banner.dart';
import 'session_act_row.dart';
import 'session_actions_panel.dart';
import 'session_acts_panel.dart';
import 'session_note_panel.dart';

/// Seuils responsive de la vue fauteuil, alignés sur
/// `design/07-handoff/00-fondations.md` (desktop ≥1024, tablette 768-1023,
/// mobile <768 — le `ProShell` casse à 720 de son côté).
const double kConsultationDesktopMinWidth = 1024;
const double kConsultationTabletMinWidth = 768;

/// Vue « séance ouverte » : bandeau patient + colonnes selon la largeur
/// (maquette `bo-praticien-core.jsx`, 3 colonnes 300 | 1fr | 280), avec le
/// module dentaire intégré : odontogramme en tête de colonne centrale
/// (tap dent → acte CCAM pré-rempli, à la Desmos) et proposition EXPLICITE
/// de mise à jour d'état de dent après un acte (jamais d'automatisme,
/// périmètre non-DM).
///
/// La dent sélectionnée vit dans le `ConsultationCliniqueBloc`
/// (`state.selectedTooth`, #4048).
class ConsultationLoadedView extends StatefulWidget {
  const ConsultationLoadedView({super.key, required this.state});

  final ConsultationCliniqueLoaded state;

  @override
  State<ConsultationLoadedView> createState() => _ConsultationLoadedViewState();
}

class _ConsultationLoadedViewState extends State<ConsultationLoadedView> {
  /// Ancre de la zone de saisie d'acte pour le bouton « Ajouter un acte »
  /// de la colonne Actions.
  final GlobalKey _actEntryAnchor = GlobalKey();

  void _scrollToActEntry() {
    final ctx = _actEntryAnchor.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 250),
        alignment: 0.1,
      );
    }
  }

  void _submitAct({
    required String code,
    required String label,
    String? tooth,
    required int amountCents,
  }) {
    context.read<ConsultationCliniqueBloc>().add(
          ConsultationCliniqueActAddRequested(
            ccamCode: code,
            label: label,
            tooth: tooth,
            amountCents: amountCents,
          ),
        );
  }

  /// Après un acte portant une dent : PROPOSE la mise à jour de
  /// l'odontogramme si la table de suggestions connaît l'acte. « Ignorer »
  /// n'écrit rien ; la validation passe par le PUT dental-chart standard.
  Future<void> _onToothActAdded(
    BuildContext context,
    ConsultationCliniqueLoaded state,
  ) async {
    final added = state.lastAddedToothAct!;
    final bloc = context.read<ConsultationCliniqueBloc>();
    final chartCubit = context.read<DentalChartCubit>();
    bloc.add(const ConsultationCliniqueToothActConsumed());

    final suggestion = suggestedToothStatusForAct(
      ccamCode: added.ccamCode,
      label: added.label,
    );
    if (suggestion == null) return;

    final chosen = await ToothStatusUpdateDialog.show(
      context,
      tooth: added.tooth,
      actLabel: added.label,
      suggestedStatus: suggestion,
    );
    if (chosen != null) {
      chartCubit.setToothStatus(added.tooth, chosen);
      await chartCubit.save();
    }
  }

  ActEntryPanel _buildEntryPanel(Map<String, ToothState>? teeth) =>
      ActEntryPanel(
        key: _actEntryAnchor,
        selectedTooth: widget.state.selectedTooth,
        teethStatus: teeth,
        onToothSelected: (tooth) => context
            .read<ConsultationCliniqueBloc>()
            .add(ConsultationCliniqueToothSelected(tooth)),
        onToothCleared: () => context
            .read<ConsultationCliniqueBloc>()
            .add(const ConsultationCliniqueToothCleared()),
        onActSubmitted: _submitAct,
      );

  /// Dent mise en avant dans le contexte clinique : la sélection courante,
  /// sinon la dernière dent traitée cette séance.
  String? get _highlightedTooth {
    final selected = widget.state.selectedTooth;
    if (selected != null) return selected;
    for (final act in widget.state.session.acts.reversed) {
      final tooth = act.tooth;
      if (tooth != null && tooth.isNotEmpty) return tooth;
    }
    return null;
  }

  Widget _buildLayouts(BuildContext context,
      {required Map<String, ToothState>? teeth, required bool dental}) {
    final highlightedTooth = _highlightedTooth;
    final moduleTile = highlightedTooth == null
        ? null
        : TreatedToothTile(tooth: highlightedTooth);
    final odontogram = dental ? const OdontogramPanel() : null;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        if (width >= kConsultationDesktopMinWidth) {
          return _DesktopLayout(
            state: widget.state,
            entryPanel: _buildEntryPanel(teeth),
            onAddAct: _scrollToActEntry,
            odontogram: odontogram,
            moduleTile: moduleTile,
          );
        }
        if (width >= kConsultationTabletMinWidth) {
          return _TabletLayout(
            state: widget.state,
            entryPanel: _buildEntryPanel(teeth),
            onAddAct: _scrollToActEntry,
            odontogram: odontogram,
            moduleTile: moduleTile,
          );
        }
        return _MobileLayout(
          state: widget.state,
          entryPanel: _buildEntryPanel(teeth),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final patientId = widget.state.session.patient?.id;
    // Sans patient (payload minimal / back en retard) : pas de module
    // dentaire, la saisie d'acte reste pleinement fonctionnelle.
    if (patientId == null) {
      return _buildLayouts(context, teeth: null, dental: false);
    }
    return BlocProvider<DentalChartCubit>(
      // Keyé sur le patient : le cubit (et son GET dental-chart) survit aux
      // rebuilds de séance (ajout d'acte) et n'est recréé qu'au changement
      // de patient.
      key: ValueKey('consultation_dental_chart_$patientId'),
      create: (_) => DentalChartCubit(
        patientId: patientId,
        getDentalChart: GetIt.instance<GetDentalChartUseCase>(),
        putDentalChart: GetIt.instance<PutDentalChartUseCase>(),
      ),
      child: BlocListener<ConsultationCliniqueBloc, ConsultationCliniqueState>(
        listenWhen: (_, current) =>
            current is ConsultationCliniqueLoaded &&
            current.lastAddedToothAct != null,
        listener: (context, state) => _onToothActAdded(
          context,
          state as ConsultationCliniqueLoaded,
        ),
        child: BlocBuilder<DentalChartCubit, DentalChartState>(
          builder: (context, chartState) => _buildLayouts(
            context,
            teeth: chartState is DentalChartLoaded ? chartState.teeth : null,
            dental: true,
          ),
        ),
      ),
    );
  }
}

class _DesktopLayout extends StatelessWidget {
  const _DesktopLayout({
    required this.state,
    required this.entryPanel,
    required this.onAddAct,
    this.odontogram,
    this.moduleTile,
  });

  final ConsultationCliniqueLoaded state;
  final Widget entryPanel;
  final VoidCallback onAddAct;
  final Widget? odontogram;
  final Widget? moduleTile;

  @override
  Widget build(BuildContext context) {
    final session = state.session;
    return Column(
      key: const Key('consultation_desktop_layout'),
      children: [
        if (state.actionInProgress)
          const LinearProgressIndicator(
              key: Key('consultation_action_progress')),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: PatientBanner(session: session),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 300,
                  child: SingleChildScrollView(
                    child: ClinicalContextPanel(
                      session: session,
                      moduleTile: moduleTile,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        if (odontogram != null) ...[
                          odontogram!,
                          const SizedBox(height: 16),
                        ],
                        SessionActsPanel(session: session),
                        const SizedBox(height: 16),
                        entryPanel,
                        const SizedBox(height: 16),
                        SessionNotePanel(
                          session: session,
                          actionInProgress: state.actionInProgress,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                SizedBox(
                  width: 280,
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        SessionActionsPanel(
                          session: session,
                          actionInProgress: state.actionInProgress,
                          onAddAct: onAddAct,
                        ),
                        if (session.currentPhase != null) ...[
                          const SizedBox(height: 16),
                          NextStepPanel(phase: session.currentPhase!),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _TabletLayout extends StatelessWidget {
  const _TabletLayout({
    required this.state,
    required this.entryPanel,
    required this.onAddAct,
    this.odontogram,
    this.moduleTile,
  });

  final ConsultationCliniqueLoaded state;
  final Widget entryPanel;
  final VoidCallback onAddAct;
  final Widget? odontogram;
  final Widget? moduleTile;

  @override
  Widget build(BuildContext context) {
    final session = state.session;
    return Column(
      key: const Key('consultation_tablet_layout'),
      children: [
        if (state.actionInProgress)
          const LinearProgressIndicator(
              key: Key('consultation_action_progress')),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: PatientBanner(session: session),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        if (odontogram != null) ...[
                          odontogram!,
                          const SizedBox(height: 16),
                        ],
                        SessionActsPanel(session: session),
                        const SizedBox(height: 16),
                        entryPanel,
                        const SizedBox(height: 16),
                        SessionNotePanel(
                          session: session,
                          actionInProgress: state.actionInProgress,
                        ),
                        const SizedBox(height: 16),
                        ClinicalContextPanel(
                          session: session,
                          moduleTile: moduleTile,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                SizedBox(
                  width: 260,
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        SessionActionsPanel(
                          session: session,
                          actionInProgress: state.actionInProgress,
                          onAddAct: onAddAct,
                        ),
                        if (session.currentPhase != null) ...[
                          const SizedBox(height: 16),
                          NextStepPanel(phase: session.currentPhase!),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Mobile : pile verticale historique (grosses cibles, odontogramme via
/// bottom-sheet coloré par l'état réel des dents), « Terminer » compact dans
/// le bandeau patient.
class _MobileLayout extends StatelessWidget {
  const _MobileLayout({required this.state, required this.entryPanel});

  final ConsultationCliniqueLoaded state;
  final Widget entryPanel;

  @override
  Widget build(BuildContext context) {
    final session = state.session;
    return Column(
      key: const Key('consultation_mobile_layout'),
      children: [
        if (state.actionInProgress)
          const LinearProgressIndicator(
              key: Key('consultation_action_progress')),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: PatientBanner(
            session: session,
            trailing: NubiaButton(
              key: const Key('complete_consultation_button'),
              size: NubiaButtonSize.sm,
              icon: Icons.check,
              label: 'Terminer',
              onPressed: state.actionInProgress || session.isFinished
                  ? null
                  : () => context.read<ConsultationCliniqueBloc>().add(
                        const ConsultationCliniqueCompleteRequested(),
                      ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: SessionNotePanel(
            session: session,
            actionInProgress: state.actionInProgress,
          ),
        ),
        entryPanel,
        if (session.acts.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                key: const Key('sterilization_scan_button'),
                icon: const Icon(Icons.qr_code_scanner_outlined, size: 18),
                label: const Text('Scanner une pochette stérilisée'),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => SterilizationScanPage(
                      // Dernier acte ajouté = "l'acte en cours" (#4139).
                      consultationActId: session.acts.last.id,
                    ),
                  ),
                ),
              ),
            ),
          ),
        const SizedBox(height: 8),
        Expanded(
          child: session.acts.isEmpty
              ? const NubiaEmptyState(
                  key: Key('consultation_empty'),
                  icon: Icons.medical_services_outlined,
                  title: 'Aucun acte enregistré',
                  subtitle: 'Recherchez un acte CCAM pour l\'ajouter.',
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: session.acts.length,
                  itemBuilder: (context, i) => SessionActRow(
                    act: session.acts[i],
                    highlighted:
                        !session.isFinished && i == session.acts.length - 1,
                  ),
                ),
        ),
      ],
    );
  }
}

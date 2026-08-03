import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

import '../consultation_clinique_bloc.dart';
import '../consultation_clinique_event.dart';
import '../consultation_clinique_state.dart';
import '../sterilization_scan_page.dart';
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
/// (maquette `bo-praticien-core.jsx`, 3 colonnes 300 | 1fr | 280).
///
/// La dent sélectionnée (#4048) vit ici en attendant sa migration dans le
/// Bloc avec l'odontogramme intégré (lot 3 de la refonte).
class ConsultationLoadedView extends StatefulWidget {
  const ConsultationLoadedView({super.key, required this.state});

  final ConsultationCliniqueLoaded state;

  @override
  State<ConsultationLoadedView> createState() => _ConsultationLoadedViewState();
}

class _ConsultationLoadedViewState extends State<ConsultationLoadedView> {
  String? _selectedTooth;

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

  ActEntryPanel _buildEntryPanel() => ActEntryPanel(
        key: _actEntryAnchor,
        selectedTooth: _selectedTooth,
        onToothSelected: (tooth) => setState(() => _selectedTooth = tooth),
        onToothCleared: () => setState(() => _selectedTooth = null),
        onActSubmitted: _submitAct,
      );

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        if (width >= kConsultationDesktopMinWidth) {
          return _DesktopLayout(
            state: widget.state,
            entryPanel: _buildEntryPanel(),
            onAddAct: _scrollToActEntry,
          );
        }
        if (width >= kConsultationTabletMinWidth) {
          return _TabletLayout(
            state: widget.state,
            entryPanel: _buildEntryPanel(),
            onAddAct: _scrollToActEntry,
          );
        }
        return _MobileLayout(
          state: widget.state,
          entryPanel: _buildEntryPanel(),
        );
      },
    );
  }
}

class _DesktopLayout extends StatelessWidget {
  const _DesktopLayout({
    required this.state,
    required this.entryPanel,
    required this.onAddAct,
  });

  final ConsultationCliniqueLoaded state;
  final Widget entryPanel;
  final VoidCallback onAddAct;

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
                    child: ClinicalContextPanel(session: session),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
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
  });

  final ConsultationCliniqueLoaded state;
  final Widget entryPanel;
  final VoidCallback onAddAct;

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
                        SessionActsPanel(session: session),
                        const SizedBox(height: 16),
                        entryPanel,
                        const SizedBox(height: 16),
                        SessionNotePanel(
                          session: session,
                          actionInProgress: state.actionInProgress,
                        ),
                        const SizedBox(height: 16),
                        ClinicalContextPanel(session: session),
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
/// bottom-sheet), « Terminer » compact dans le bandeau patient.
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

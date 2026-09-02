import 'dart:async';

import 'package:get_it/get_it.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:nubia_app_shell/nubia_app_shell.dart' hide ProConfig;
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'cr_template_picker.dart';
import 'widgets/center_column.dart';
import 'widgets/consultation_historique_view.dart';
import 'widgets/consultation_layout_breakpoints.dart';
import 'widgets/context_column.dart';
import 'widgets/patient_identity_bar.dart';
import 'widgets/recent_sessions_box.dart';
import 'widgets/side_column.dart';
import '../../pro_config.dart';
import '../../router/app_router.dart';
import '../../session/pro_auth_cubit.dart';
import 'consultation_clinique_bloc.dart';
import 'consultation_clinique_event.dart';
import 'consultation_clinique_state.dart';

/// Body-only content for the consultation au fauteuil.
/// Requires [ConsultationCliniqueBloc] to be provided via [BlocProvider] by the caller.
class ConsultationCliniqueBody extends StatefulWidget {
  final String? consultationId;

  const ConsultationCliniqueBody({super.key, this.consultationId});

  @override
  State<ConsultationCliniqueBody> createState() =>
      _ConsultationCliniqueBodyState();
}

class _ConsultationCliniqueBodyState extends State<ConsultationCliniqueBody> {
  @override
  void initState() {
    super.initState();
    final id = widget.consultationId;
    if (id != null) {
      context
          .read<ConsultationCliniqueBloc>()
          .add(ConsultationCliniqueLoadRequested(id));
    } else {
      context
          .read<ConsultationCliniqueBloc>()
          .add(const ConsultationHistoriqueRequested());
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<ConsultationCliniqueBloc, ConsultationCliniqueState>(
      // #3403 — surface l'erreur d'action (ex. 403 « Action non autorisée »)
      // via snackbar, puis consomme le message pour éviter les doublons.
      // #4057/#4058 — alerte clinique bloquante : dialogue dédié (pas un
      // snackbar), affiché avant tout retour à la saisie.
      listenWhen: (_, current) =>
          current is ConsultationCliniqueLoaded &&
          (current.actionError != null || current.clinicalRiskWarning != null),
      listener: (context, state) async {
        if (state is! ConsultationCliniqueLoaded) return;
        if (state.clinicalRiskWarning != null) {
          await showDialog<void>(
            context: context,
            barrierDismissible: false,
            builder: (dialogContext) => AlertDialog(
              key: const Key('clinical_risk_warning_dialog'),
              icon: Icon(Icons.warning_amber_rounded,
                  color: Theme.of(dialogContext).colorScheme.error),
              title: const Text('Alerte clinique'),
              content: Text(state.clinicalRiskWarning!),
              actions: [
                NubiaButton(
                  key: const Key('clinical_risk_warning_dismiss'),
                  label: 'Compris',
                  onPressed: () => Navigator.of(dialogContext).pop(),
                ),
              ],
            ),
          );
          if (context.mounted) {
            context
                .read<ConsultationCliniqueBloc>()
                .add(const ConsultationCliniqueClinicalRiskWarningConsumed());
          }
          return;
        }
        if (state.actionError != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              key: const Key('consultation_action_error'),
              content: Text(state.actionError!),
            ),
          );
          context
              .read<ConsultationCliniqueBloc>()
              .add(const ConsultationCliniqueActionErrorConsumed());
        }
      },
      builder: (context, state) {
        if (state is ConsultationCliniqueInitial) {
          return const Center(
            key: Key('consultation_idle'),
            child: CircularProgressIndicator(),
          );
        }
        if (state is ConsultationCliniqueLoading) {
          return const Center(
            key: Key('consultation_loading'),
            child: CircularProgressIndicator(),
          );
        }
        if (state is ConsultationCliniqueError) {
          return NubiaErrorWidget(
            key: const Key('consultation_error'),
            message: state.message,
          );
        }
        if (state is ConsultationCliniqueLoaded) {
          return _LoadedView(state: state);
        }
        if (state is ConsultationCliniqueCompleted) {
          return const NubiaEmptyState(
            key: Key('consultation_completed'),
            icon: Icons.check_circle_outline,
            title: 'Consultation terminée',
            subtitle: 'Les actes ont été enregistrés.',
          );
        }
        if (state is ConsultationHistoriqueLoaded) {
          return HistoriqueView(sessions: state.sessions);
        }
        return const SizedBox.shrink();
      },
    );
  }
}

// ---------------------------------------------------------------------------

/// Entry point for direct-URL / deep-link navigation to `/consultation`.
/// Renders inside the shared [ProShell] (rail de navigation permanent en
/// desktop, cf. #4944) plutôt qu'un Scaffold isolé — la destination
/// « Consultation » est active et les autres destinations restent
/// accessibles depuis le rail.
/// Requires [ConsultationCliniqueBloc] to be provided via [BlocProvider] by the caller.
class ConsultationCliniquePage extends StatelessWidget {
  final String? consultationId;

  const ConsultationCliniquePage({super.key, this.consultationId});

  @override
  Widget build(BuildContext context) {
    final session = switch (context.watch<ProAuthCubit>().state) {
      AuthAuthenticated(:final session) => session,
      _ => const AuthSession(
          kind: UserKind.pro,
          userId: 'me',
          role: ProConfig.role,
        ),
    };

    return ProShell(
      config: ProConfig.shellConfig,
      session: session,
      currentRoute: AppRouter.consultation,
      onNavigate: (destination) => context.go(destination.route),
      notificationRepository: GetIt.instance<NotificationRepository>(),
      bodyBuilder: (ctx, destination) {
        if (destination.route == AppRouter.consultation) {
          // #6190 — go_router réutilise le même State en naviguant de
          // /consultation vers /consultation?id=X (même route, param de
          // query qui change) : sans Key dérivée de consultationId,
          // initState() (qui déclenche le chargement) ne se rejoue jamais et
          // le clic sur une carte de l'historique reste sans effet visible.
          return ConsultationCliniqueBody(
            key: ValueKey(consultationId),
            consultationId: consultationId,
          );
        }
        return Center(
          child: NubiaEmptyState(
            icon: Icons.construction_outlined,
            title: destination.label,
          ),
        );
      },
      onSignOut: () => context.read<ProAuthCubit>().signOut(),
    );
  }
}

// ---------------------------------------------------------------------------

class _LoadedView extends StatefulWidget {
  const _LoadedView({required this.state});
  final ConsultationCliniqueLoaded state;

  @override
  State<_LoadedView> createState() => _LoadedViewState();
}

class _LoadedViewState extends State<_LoadedView> {
  late final TextEditingController _noteController;

  /// Focus partagé entre la recherche globale de la barre du haut (#4948) et
  /// la recherche d'acte CCAM du volet droit (`CcamPicker`) : en l'absence
  /// d'une recherche transverse (patient/ordonnance), la barre du haut ouvre
  /// la palette d'acte existante — même cible que le raccourci ⌘K (#4941).
  final FocusNode _actSearchFocusNode = FocusNode();

  /// Débounce de l'auto-save de la note de séance (#4943, #4963) — la note
  /// n'a plus de bouton d'enregistrement manuel explicite : elle se
  /// sauvegarde 1,5 s après la dernière frappe.
  Timer? _noteSaveDebounce;

  void _onNoteChanged(String value) {
    _noteSaveDebounce?.cancel();
    _noteSaveDebounce = Timer(const Duration(milliseconds: 1500), () {
      context
          .read<ConsultationCliniqueBloc>()
          .add(ConsultationCliniqueNoteSaveRequested(value));
    });
  }

  /// Enregistrement immédiat de la note (#4942, ⌘S) — force la sauvegarde
  /// sans attendre le débounce de l'auto-save : annule le timer en attente
  /// puis dispatche l'événement avec le texte courant de la note.
  void _saveNoteNow() {
    _noteSaveDebounce?.cancel();
    context
        .read<ConsultationCliniqueBloc>()
        .add(ConsultationCliniqueNoteSaveRequested(_noteController.text));
  }

  /// Dent sélectionnée pour le prochain acte CCAM (#4048) — pré-remplit
  /// `CcamPicker`/`CcamActEditorDialog` au lieu de la saisie texte libre.
  /// L'arcade permanente de la colonne centrale (#4949, `DentalStatusBox`)
  /// remplace la bottom sheet historique ; un tap sur la dent déjà
  /// sélectionnée la désélectionne.
  String? _selectedTooth;

  void _onToothTap(String code) {
    setState(() => _selectedTooth = _selectedTooth == code ? null : code);
  }

  /// Efface la dent sélectionnée depuis la croix de la pastille du panneau
  /// « Ajouter un acte » (#4959).
  void _clearSelectedTooth() {
    setState(() => _selectedTooth = null);
  }

  /// Ouvre le sélecteur de modèle de CR (#4125) et pré-remplit la note de
  /// séance avec le corps du modèle choisi — trié par pertinence selon le
  /// `ccam_code` du premier acte ajouté à la séance.
  Future<void> _pickCrTemplate() async {
    final firstActCcamCode = widget.state.session.acts.isEmpty
        ? null
        : widget.state.session.acts.first.ccamCode;
    final template = await CrTemplatePicker.show(
      context,
      loadTemplates: () async {
        final result = await GetIt.instance<ListCrTemplatesUseCase>().call();
        return result.fold((_) => <CrTemplate>[], (templates) => templates);
      },
      firstActCcamCode: firstActCcamCode,
    );
    if (template != null) {
      _noteController.text = template.bodyTemplate;
      _onNoteChanged(template.bodyTemplate);
    }
  }

  @override
  void initState() {
    super.initState();
    _noteController = TextEditingController(text: widget.state.session.note);
  }

  @override
  void didUpdateWidget(covariant _LoadedView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Ne resynchronise le champ que si la note vient réellement de changer
    // côté serveur (ex. rechargement après enregistrement) : évite d'écraser
    // une saisie en cours à chaque rebuild de séance (ex. ajout d'acte).
    if (widget.state.session.note != oldWidget.state.session.note &&
        widget.state.session.note != _noteController.text) {
      _noteController.text = widget.state.session.note ?? '';
    }
  }

  @override
  void dispose() {
    _noteSaveDebounce?.cancel();
    _noteController.dispose();
    _actSearchFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final session = state.session;
    final textTheme = Theme.of(context).textTheme;

    final body = _buildBody(context, state, session, textTheme);
    final patientId = session.patientId;
    if (patientId == null) return body;

    // Colonne de contexte gauche (≥ 1280 px) — encart « Dernières séances »
    // du patient de la séance en cours (#4937).
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 1280) return body;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 280,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 0, 16),
                child: RecentSessionsBox(
                  patientId: patientId,
                  excludeSessionId: session.id,
                ),
              ),
            ),
            Expanded(child: body),
          ],
        );
      },
    );
  }

  Widget _buildBody(
    BuildContext context,
    ConsultationCliniqueLoaded state,
    ClinicalSession session,
    TextTheme textTheme,
  ) {
    return Column(
      children: [
        if (state.actionInProgress)
          const LinearProgressIndicator(
              key: Key('consultation_action_progress')),
        PatientIdentityBar(
          session: session,
          textTheme: textTheme,
          globalSearchFocusNode: _actSearchFocusNode,
          onCompletePressed: state.actionInProgress || session.isFinished
              ? null
              : () => context.read<ConsultationCliniqueBloc>().add(
                    const ConsultationCliniqueCompleteRequested(),
                  ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              // #4935 — bascule décidée sur la largeur *disponible* du corps
              // (jamais MediaQuery : la fenêtre se redimensionne et l'app
              // tourne en écran partagé).
              final isAtLeastTwoColumns = width >= kTwoColumnBreakpoint;

              final centerColumn = CenterColumn(
                key: const Key('consultation_center_panel'),
                session: session,
                selectedTooth: _selectedTooth,
                onToothTap: _onToothTap,
                scrollable: isAtLeastTwoColumns,
              );
              final sideColumn = SideColumn(
                key: const Key('consultation_side_panel'),
                textTheme: textTheme,
                noteController: _noteController,
                onPickCrTemplate: _pickCrTemplate,
                onNoteChanged: _onNoteChanged,
                onSaveNote: _saveNoteNow,
                lastNoteSavedAt: state.lastNoteSavedAt,
                selectedTooth: _selectedTooth,
                onClearSelectedTooth: _clearSelectedTooth,
                actSearchFocusNode: _actSearchFocusNode,
                // #3402 — l'éditeur d'acte fournit la dent + le montant,
                // transmis au POST .../acts (le total reflète alors la
                // somme des montants).
                onActSubmitted: ({
                  required String code,
                  required String label,
                  String? tooth,
                  required int amountCents,
                }) =>
                    context.read<ConsultationCliniqueBloc>().add(
                          ConsultationCliniqueActAddRequested(
                            ccamCode: code,
                            label: label,
                            tooth: tooth,
                            amountCents: amountCents,
                          ),
                        ),
                scrollable: isAtLeastTwoColumns,
                // #4939 — dès 1280 px la note de séance devient permanente
                // (co-visible avec « Ajouter un acte », jamais sous la ligne
                // de flottaison). Sous ce seuil : comportement tablette
                // d'origine (colonne défilante) inchangé.
                pinnedNote: width >= kThreeColumnBreakpoint,
              );

              if (width >= kThreeColumnBreakpoint) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: kContextColumnWidth,
                      child: ContextColumn(
                        key: const Key('consultation_context_panel'),
                        alerts: session.medicalAlerts,
                        patientId: session.patientId,
                        activePlan: session.activePlan,
                      ),
                    ),
                    Expanded(child: centerColumn),
                    SizedBox(width: kSideColumnWidth, child: sideColumn),
                  ],
                );
              }
              if (isAtLeastTwoColumns) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: centerColumn),
                    SizedBox(width: kSideColumnWidth, child: sideColumn),
                  ],
                );
              }
              return SingleChildScrollView(
                key: const Key('consultation_single_column'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [centerColumn, sideColumn],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

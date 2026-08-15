import 'dart:async';

import 'package:get_it/get_it.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'ccam_picker.dart';
import 'cr_template_picker.dart';
import 'sterilization_scan_page.dart';
import 'widgets/recent_sessions_box.dart';
import '../dental_chart/tooth_grid.dart';
import '../../router/app_router.dart';
import 'consultation_clinique_bloc.dart';
import 'consultation_clinique_event.dart';
import 'consultation_clinique_state.dart';
import 'widgets/patient_alerts_box.dart';

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
          return _HistoriqueView(sessions: state.sessions);
        }
        return const SizedBox.shrink();
      },
    );
  }
}

// ---------------------------------------------------------------------------

/// Full-page scaffold for direct-URL navigation.
/// Requires [ConsultationCliniqueBloc] to be provided via [BlocProvider] by the caller.
class ConsultationCliniquePage extends StatelessWidget {
  final String? consultationId;

  const ConsultationCliniquePage({super.key, this.consultationId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Consultation')),
      body: ConsultationCliniqueBody(consultationId: consultationId),
    );
  }
}

// ---------------------------------------------------------------------------

/// Seuils de bascule imposés par la maquette design-v2 (#4935) — décidés via
/// `LayoutBuilder` sur la largeur *disponible*, jamais `MediaQuery`, car
/// l'app peut tourner en écran partagé et se redimensionner.
const _kThreeColumnBreakpoint = 1280.0;
const _kTwoColumnBreakpoint = 900.0;
const _kContextColumnWidth = 288.0;
const _kSideColumnWidth = 376.0;

class _LoadedView extends StatefulWidget {
  const _LoadedView({required this.state});
  final ConsultationCliniqueLoaded state;

  @override
  State<_LoadedView> createState() => _LoadedViewState();
}

class _LoadedViewState extends State<_LoadedView> {
  late final TextEditingController _noteController;

  /// Débounce de l'auto-save de la note de séance (#4943) — la note n'a plus
  /// de bouton d'enregistrement manuel explicite : elle se sauvegarde après
  /// une pause de frappe.
  Timer? _noteSaveDebounce;

  void _onNoteChanged(String value) {
    _noteSaveDebounce?.cancel();
    _noteSaveDebounce = Timer(const Duration(milliseconds: 800), () {
      context
          .read<ConsultationCliniqueBloc>()
          .add(ConsultationCliniqueNoteSaveRequested(value));
    });
  }

  /// Dent sélectionnée pour le prochain acte CCAM (#4048) — pré-remplit
  /// `CcamPicker`/`CcamActEditorDialog` au lieu de la saisie texte libre.
  String? _selectedTooth;

  Future<void> _pickTooth() async {
    final tooth = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: ToothGrid(
          quadrants: FdiQuadrants.permanent,
          keyPrefix: 'act_tooth_picker',
          // Poste cabinet (PC) : tactile mural ou souris dans la même
          // séance, cibles 44×50 px (#4940) au lieu des 32×32 par défaut.
          toothSize: const Size(44, 50),
          colorFor: (code) => code == _selectedTooth
              ? Theme.of(ctx).colorScheme.primary
              : Colors.grey.shade100,
          onTap: (code) => Navigator.of(ctx).pop(code),
        ),
      ),
    );
    if (tooth != null) {
      setState(() => _selectedTooth = tooth);
    }
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
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: NubiaCard(
            key: const Key('patient_identity_bar'),
            child: Row(
              children: [
                NubiaAvatar(
                  initials: _patientInitials(session.patientName),
                  radius: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              session.patientName?.trim().isNotEmpty == true
                                  ? session.patientName!.trim()
                                  : 'Patient',
                              style: textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w600),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          StatusPill(
                            label: session.isCancelled
                                ? 'Annulée'
                                : session.isCompleted
                                    ? 'Terminée'
                                    : 'Séance en cours',
                            variant: session.isCancelled
                                ? StatusPillVariant.warning
                                : session.isCompleted
                                    ? StatusPillVariant.success
                                    : StatusPillVariant.info,
                            icon: session.isCancelled || session.isCompleted
                                ? null
                                : Icons.info_outline,
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      _PatientIdentitySubtitle(
                        birthDate: session.patientBirthDate,
                        practitionerName: session.practitionerName,
                        textTheme: textTheme,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                _SessionTotal(
                  // #3402 — même calcul que le total transmis au POST
                  // .../acts : somme des `amountCents` des actes enregistrés.
                  totalCents: session.acts.fold<int>(
                      0, (sum, act) => sum + (act.amountCents ?? 0)),
                  textTheme: textTheme,
                ),
                const SizedBox(width: 12),
                NubiaButton(
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
              ],
            ),
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              // #4935 — bascule décidée sur la largeur *disponible* du corps
              // (jamais MediaQuery : la fenêtre se redimensionne et l'app
              // tourne en écran partagé).
              final isAtLeastTwoColumns = width >= _kTwoColumnBreakpoint;

              final centerColumn = _CenterColumn(
                key: const Key('consultation_center_panel'),
                session: session,
                selectedTooth: _selectedTooth,
                onPickTooth: _pickTooth,
                onClearTooth: () => setState(() => _selectedTooth = null),
                scrollable: isAtLeastTwoColumns,
              );
              final sideColumn = _SideColumn(
                key: const Key('consultation_side_panel'),
                textTheme: textTheme,
                noteController: _noteController,
                onPickCrTemplate: _pickCrTemplate,
                onNoteChanged: _onNoteChanged,
                lastNoteSavedAt: state.lastNoteSavedAt,
                selectedTooth: _selectedTooth,
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
              );

              if (width >= _kThreeColumnBreakpoint) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: _kContextColumnWidth,
                      child: _ContextColumn(
                        key: const Key('consultation_context_panel'),
                        alerts: session.medicalAlerts,
                      ),
                    ),
                    Expanded(child: centerColumn),
                    SizedBox(width: _kSideColumnWidth, child: sideColumn),
                  ],
                );
              }
              if (isAtLeastTwoColumns) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: centerColumn),
                    SizedBox(width: _kSideColumnWidth, child: sideColumn),
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

/// Colonne « Contexte » (288 px, ≥ 1280 px uniquement) — scaffold #4935.
/// En tête, l'encart « Alertes du dossier » (#4936) quand le dossier porte
/// des alertes médicales passives ([alerts] non vide) ; le reste (historique,
/// plan de traitement) reste un squelette « à venir », tickets dédiés.
class _ContextColumn extends StatelessWidget {
  const _ContextColumn({super.key, required this.alerts});

  final List<MedicalAlert> alerts;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(0, 0, 8, 8),
      child: Column(
        // La clé `consultation_context_column_layout` (#4936) n'existe que
        // lorsqu'un encart d'alertes est réellement rendu — sinon la colonne
        // reste le simple squelette « à venir ».
        key: alerts.isEmpty
            ? null
            : const Key('consultation_context_column_layout'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (alerts.isNotEmpty) ...[
            PatientAlertsBox(alerts: alerts),
            const SizedBox(height: 12),
          ],
          NubiaCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Contexte patient', style: textTheme.titleSmall),
                const SizedBox(height: 8),
                Text(
                  'Historique et plan de traitement arrivent bientôt.',
                  style: textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Colonne « Arcade + actes » — sélecteur de dent et liste des actes
/// enregistrés. `scrollable` gère son propre défilement en layout 2/3
/// colonnes (hauteur bornée par la Row) ; en 1 colonne elle est déjà
/// intégrée au `SingleChildScrollView` parent.
class _CenterColumn extends StatelessWidget {
  const _CenterColumn({
    super.key,
    required this.session,
    required this.selectedTooth,
    required this.onPickTooth,
    required this.onClearTooth,
    required this.scrollable,
  });

  final ClinicalSession session;
  final String? selectedTooth;
  final VoidCallback onPickTooth;
  final VoidCallback onClearTooth;
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  key: const Key('act_tooth_picker_button'),
                  onPressed: onPickTooth,
                  icon: const Icon(Icons.grid_view_outlined, size: 18),
                  label: Text(
                    selectedTooth == null
                        ? 'Choisir une dent'
                        : 'Dent $selectedTooth',
                  ),
                ),
              ),
              if (selectedTooth != null)
                IconButton(
                  key: const Key('act_tooth_picker_clear'),
                  icon: const Icon(Icons.close),
                  tooltip: 'Retirer la dent sélectionnée',
                  onPressed: onClearTooth,
                ),
            ],
          ),
        ),
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
                      // Dernier acte ajouté = "l'acte en cours" (#4139),
                      // même convention que _pickCrTemplate (session.acts
                      // trié created_at ASC côté back).
                      consultationActId: session.acts.last.id,
                    ),
                  ),
                ),
              ),
            ),
          ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: session.acts.isEmpty
              ? const NubiaEmptyState(
                  key: Key('consultation_empty'),
                  icon: Icons.medical_services_outlined,
                  title: 'Aucun acte enregistré',
                  subtitle: 'Recherchez un acte CCAM pour l\'ajouter.',
                )
              : ListView.builder(
                  key: const Key('consultation_acts_list'),
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: session.acts.length,
                  itemBuilder: (context, i) => _ActTile(act: session.acts[i]),
                ),
        ),
      ],
    );
    return scrollable ? SingleChildScrollView(child: content) : content;
  }
}

/// Colonne « Saisie + note » (376 px) — recherche/ajout d'acte CCAM et note
/// de séance. `scrollable` suit la même logique que [_CenterColumn].
class _SideColumn extends StatelessWidget {
  const _SideColumn({
    super.key,
    required this.textTheme,
    required this.noteController,
    required this.onPickCrTemplate,
    required this.onNoteChanged,
    required this.lastNoteSavedAt,
    required this.selectedTooth,
    required this.onActSubmitted,
    required this.scrollable,
  });

  final TextTheme textTheme;
  final TextEditingController noteController;
  final VoidCallback onPickCrTemplate;
  final ValueChanged<String> onNoteChanged;
  final DateTime? lastNoteSavedAt;
  final String? selectedTooth;
  final void Function({
    required String code,
    required String label,
    String? tooth,
    required int amountCents,
  }) onActSubmitted;
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: NubiaCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: Text(
                        'Note de séance',
                        style: textTheme.titleSmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    TextButton.icon(
                      key: const Key('cr_template_picker_button'),
                      onPressed: onPickCrTemplate,
                      icon: const Icon(Icons.description_outlined, size: 18),
                      label: const Text('Modèle'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  key: const Key('consultation_note_field'),
                  controller: noteController,
                  maxLines: 4,
                  onChanged: onNoteChanged,
                  decoration: const InputDecoration(
                    hintText: 'Observations cliniques...',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                _NoteSaveStatus(lastSavedAt: lastNoteSavedAt),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: CcamPicker(
            key: const Key('ccam_picker'),
            useCase: GetIt.instance<GetActsUseCase>(),
            favoritesUseCase: GetIt.instance<FavoriteActsUseCase>(),
            // #4048 — la dent choisie via le schéma dentaire pré-remplit
            // l'éditeur d'acte au lieu de la saisie texte libre.
            selectedTooth: selectedTooth,
            onActSubmitted: onActSubmitted,
          ),
        ),
      ],
    );
    return scrollable ? SingleChildScrollView(child: content) : content;
  }
}

/// Indicateur d'état de l'auto-save de la note de séance (#4943) —
/// remplace le bouton « Enregistrer la note » : icône `cloud_done` + horaire
/// du dernier enregistrement réussi, rien tant qu'aucun enregistrement n'a
/// encore eu lieu. Le badge ⌘S rappelle le raccourci manuel — son
/// déclenchement effectif est traité par un ticket dédié.
class _NoteSaveStatus extends StatelessWidget {
  const _NoteSaveStatus({required this.lastSavedAt});

  final DateTime? lastSavedAt;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    final textTheme = Theme.of(context).textTheme;
    final savedAt = lastSavedAt;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        if (savedAt != null)
          Row(
            key: const Key('note_save_status'),
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_done, size: 16, color: tokens.successFg),
              const SizedBox(width: 4),
              Text(
                'Enregistré à ${_formatTime(savedAt)}',
                style: textTheme.bodySmall?.copyWith(color: tokens.successFg),
              ),
            ],
          )
        else
          const SizedBox.shrink(),
        const NubiaBadge.label(label: '⌘S'),
      ],
    );
  }
}

/// Heure courte HH:MM (24 h, heure locale) — format imposé par la maquette
/// design-v2 pour l'indicateur d'auto-save de la note (#4943).
String _formatTime(DateTime dt) {
  final d = dt.toLocal();
  final hh = d.hour.toString().padLeft(2, '0');
  final min = d.minute.toString().padLeft(2, '0');
  return '$hh:$min';
}

/// Sous-titre de la barre d'identité patient (#4945) — « âge ans · né(e) le
/// JJ/MM/AAAA · praticien ». N'affiche que les segments dont la donnée est
/// disponible (ex. date de naissance absente du dossier patient).
class _PatientIdentitySubtitle extends StatelessWidget {
  const _PatientIdentitySubtitle({
    required this.birthDate,
    required this.practitionerName,
    required this.textTheme,
  });

  final DateTime? birthDate;
  final String? practitionerName;
  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    final practitioner = practitionerName?.trim();
    final parts = <String>[
      if (birthDate != null) '${_age(birthDate!)} ans',
      if (birthDate != null) 'né(e) le ${_formatBirthDate(birthDate!)}',
      if (practitioner != null && practitioner.isNotEmpty) practitioner,
    ];
    if (parts.isEmpty) return const SizedBox.shrink();
    return Text(
      parts.join(' · '),
      style: textTheme.bodySmall?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}

/// Total de la séance, barre d'identité patient (#4946) : libellé « TOTAL
/// SÉANCE » en capitales grises + montant en chiffres tabulaires, aligné à
/// droite juste avant le bouton « Terminer ». Réutilise le formateur euros
/// commun du design system ([formatQuoteCents]) pour rester cohérent avec le
/// reste de l'app.
class _SessionTotal extends StatelessWidget {
  const _SessionTotal({required this.totalCents, required this.textTheme});

  final int totalCents;
  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const Key('consultation_session_total'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          'TOTAL SÉANCE',
          style: textTheme.labelSmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        Text(
          formatQuoteCents(totalCents),
          style: textTheme.headlineSmall?.copyWith(
            fontFeatures: tabularFigures,
          ),
        ),
      ],
    );
  }
}

/// Initiales (max 2 lettres) du patient pour l'avatar de la barre d'identité
/// (#4945) — même convention que `waiting_room_page.dart::_initials`.
String _patientInitials(String? patientName) {
  final name = patientName?.trim() ?? '';
  final parts =
      name.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
  return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
      .toUpperCase();
}

/// Âge en années révolues à partir d'une date de naissance (heure locale).
int _age(DateTime birthDate) {
  final now = DateTime.now();
  final d = birthDate.toLocal();
  var age = now.year - d.year;
  if (now.month < d.month || (now.month == d.month && now.day < d.day)) {
    age--;
  }
  return age;
}

/// Date de naissance JJ/MM/AAAA (heure locale) — format imposé par la
/// maquette design-v2 pour la barre d'identité patient (#4945).
String _formatBirthDate(DateTime dt) {
  final d = dt.toLocal();
  final dd = d.day.toString().padLeft(2, '0');
  final mm = d.month.toString().padLeft(2, '0');
  return '$dd/$mm/${d.year}';
}

/// Formatte un montant en centimes vers un libellé euros.
String _euros(int cents) => '${(cents / 100).toStringAsFixed(2)} €';

/// Date courte JJ/MM (heure locale) — réutilisée par [_HistoriqueTile] et par
/// `RecentSessionsBox` (#4937, encart « Dernières séances ») pour éviter de
/// dupliquer le format de date.
String formatShortDate(DateTime dt) {
  final d = dt.toLocal();
  final dd = d.day.toString().padLeft(2, '0');
  final mm = d.month.toString().padLeft(2, '0');
  return '$dd/$mm';
}

// ---------------------------------------------------------------------------

class _ActTile extends StatelessWidget {
  const _ActTile({required this.act});
  final ClinicalAct act;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final subtitle = act.tooth != null && act.tooth!.isNotEmpty
        ? '${act.ccamCode} · Dent ${act.tooth}'
        : act.ccamCode;

    return ListRow(
      key: Key('act_${act.id}'),
      leading: CircleAvatar(
        radius: 20,
        backgroundColor: cs.primaryContainer,
        child: Icon(Icons.medical_services_outlined,
            size: 20, color: cs.onPrimaryContainer),
      ),
      title: act.label,
      subtitle: subtitle,
      trailing: act.amountCents != null
          ? Text(
              _euros(act.amountCents!),
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            )
          : null,
    );
  }
}

// ---------------------------------------------------------------------------

class _HistoriqueView extends StatefulWidget {
  const _HistoriqueView({required this.sessions});
  final List<ClinicalSession> sessions;

  @override
  State<_HistoriqueView> createState() => _HistoriqueViewState();
}

class _HistoriqueViewState extends State<_HistoriqueView> {
  Set<String> _selection = {};

  static const _segments = [
    ButtonSegment<String>(
      value: 'in_progress',
      label: Text('En cours'),
    ),
    ButtonSegment<String>(
      value: 'completed',
      label: Text('Terminée'),
    ),
    ButtonSegment<String>(
      value: 'cancelled',
      label: Text('Annulée'),
    ),
  ];

  List<ClinicalSession> get _filtered {
    if (_selection.isEmpty) return widget.sessions;
    return widget.sessions.where((s) => _selection.contains(s.status)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: SegmentedButton<String>(
            key: const Key('historique_filter'),
            segments: _segments,
            selected: _selection,
            onSelectionChanged: (s) => setState(() => _selection = s),
            multiSelectionEnabled: false,
            emptySelectionAllowed: true,
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? const NubiaEmptyState(
                  key: Key('historique_empty'),
                  icon: Icons.medical_services_outlined,
                  title: 'Aucune consultation',
                )
              : ListView.builder(
                  key: const Key('historique_list'),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: filtered.length,
                  itemBuilder: (_, i) => _HistoriqueTile(session: filtered[i]),
                ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

class _HistoriqueTile extends StatelessWidget {
  const _HistoriqueTile({required this.session});
  final ClinicalSession session;

  String get _statusLabel {
    switch (session.status) {
      case 'completed':
        return 'Terminée';
      case 'in_progress':
        return 'En cours';
      case 'cancelled':
        return 'Annulée';
      default:
        return session.status;
    }
  }

  String _formatStart(DateTime dt) {
    final d = dt.toLocal();
    final hh = d.hour.toString().padLeft(2, '0');
    final min = d.minute.toString().padLeft(2, '0');
    return '${formatShortDate(dt)} $hh:$min';
  }

  StatusPillVariant get _statusVariant {
    switch (session.status) {
      case 'completed':
        return StatusPillVariant.success;
      case 'in_progress':
        return StatusPillVariant.info;
      case 'cancelled':
        return StatusPillVariant.warning;
      default:
        return StatusPillVariant.info;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // #3403 — attribue la séance à son praticien pour distinguer visuellement
    // la consultation d'un confrère (l'ajout d'acte y sera refusé, 403).
    final practitioner = session.practitionerName?.trim();
    final base = session.startedAt != null
        ? '${_formatStart(session.startedAt!)} · $_statusLabel'
        : _statusLabel;
    final subtitle = practitioner != null && practitioner.isNotEmpty
        ? '$base · $practitioner'
        : base;
    return ListRow(
      key: Key('historique_${session.id}'),
      leading: CircleAvatar(
        radius: 20,
        backgroundColor: cs.primaryContainer,
        child: Icon(Icons.medical_services_outlined,
            size: 20, color: cs.onPrimaryContainer),
      ),
      // Nom du patient en titre (#3371) — l'UUID reste dans la Key.
      title: session.patientName?.trim().isNotEmpty == true
          ? session.patientName!
          : 'Consultation · ${session.acts.length} acte(s)',
      subtitle: subtitle,
      trailing: StatusPill(label: _statusLabel, variant: _statusVariant),
      // #3367 : la carte doit ouvrir la séance (aucune autre voie d'accès).
      onTap: () =>
          GoRouter.of(context).go('${AppRouter.consultation}?id=${session.id}'),
    );
  }
}

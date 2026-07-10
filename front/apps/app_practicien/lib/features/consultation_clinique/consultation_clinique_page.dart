import 'package:get_it/get_it.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'ccam_picker.dart';
import '../../router/app_router.dart';
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
      listenWhen: (_, current) =>
          current is ConsultationCliniqueLoaded && current.actionError != null,
      listener: (context, state) {
        if (state is ConsultationCliniqueLoaded && state.actionError != null) {
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

class _LoadedView extends StatefulWidget {
  const _LoadedView({required this.state});
  final ConsultationCliniqueLoaded state;

  @override
  State<_LoadedView> createState() => _LoadedViewState();
}

class _LoadedViewState extends State<_LoadedView> {
  late final TextEditingController _noteController;

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
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final session = state.session;
    final textTheme = Theme.of(context).textTheme;
    final totalCents = session.acts.fold<int>(
      0,
      (sum, a) => sum + (a.amountCents ?? 0),
    );

    return Column(
      children: [
        if (state.actionInProgress)
          const LinearProgressIndicator(
              key: Key('consultation_action_progress')),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: NubiaCard(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text('Consultation au fauteuil',
                              style: textTheme.titleMedium),
                          const SizedBox(width: 8),
                          StatusPill(
                            label:
                                session.isCompleted ? 'Terminée' : 'En cours',
                            variant: session.isCompleted
                                ? StatusPillVariant.success
                                : StatusPillVariant.info,
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${session.acts.length} acte(s) CCAM · ${_euros(totalCents)}',
                        style: textTheme.bodySmall?.copyWith(
                          fontFeatures: const [FontFeature.tabularFigures()],
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                NubiaButton(
                  key: const Key('complete_consultation_button'),
                  size: NubiaButtonSize.sm,
                  icon: Icons.check,
                  label: 'Terminer',
                  onPressed: state.actionInProgress || session.isCompleted
                      ? null
                      : () => context.read<ConsultationCliniqueBloc>().add(
                            const ConsultationCliniqueCompleteRequested(),
                          ),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: NubiaCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Note de séance', style: textTheme.titleSmall),
                const SizedBox(height: 8),
                TextField(
                  key: const Key('consultation_note_field'),
                  controller: _noteController,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    hintText: 'Observations cliniques...',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: NubiaButton(
                    key: const Key('save_note_button'),
                    size: NubiaButtonSize.sm,
                    icon: Icons.save_outlined,
                    label: 'Enregistrer la note',
                    onPressed: state.actionInProgress
                        ? null
                        : () => context.read<ConsultationCliniqueBloc>().add(
                              ConsultationCliniqueNoteSaveRequested(
                                  _noteController.text),
                            ),
                  ),
                ),
              ],
            ),
          ),
        ),
        CcamPicker(
          key: const Key('ccam_picker'),
          useCase: GetIt.instance<GetActsUseCase>(),
          // #3402 — l'éditeur d'acte fournit la dent + le montant, transmis au
          // POST .../acts (le total reflète alors la somme des montants).
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
                  itemBuilder: (context, i) => _ActTile(act: session.acts[i]),
                ),
        ),
      ],
    );
  }
}

/// Formatte un montant en centimes vers un libellé euros.
String _euros(int cents) => '${(cents / 100).toStringAsFixed(2)} €';

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
      value: 'interrupted',
      label: Text('Interrompue'),
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
      case 'interrupted':
        return 'Interrompue';
      default:
        return session.status;
    }
  }

  String _formatStart(DateTime dt) {
    final d = dt.toLocal();
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    final hh = d.hour.toString().padLeft(2, '0');
    final min = d.minute.toString().padLeft(2, '0');
    return '$dd/$mm $hh:$min';
  }

  StatusPillVariant get _statusVariant {
    switch (session.status) {
      case 'completed':
        return StatusPillVariant.success;
      case 'in_progress':
        return StatusPillVariant.info;
      case 'interrupted':
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

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'ccam_picker.dart';
import 'consultation_clinique_bloc.dart';
import 'consultation_clinique_event.dart';
import 'consultation_clinique_state.dart';

/// Consultation au fauteuil — gated par [includeClinical] au niveau du router.
/// Affiche les actes CCAM de la session et permet de clore la consultation.
/// [consultationId] est passé en query param `?id=` depuis l'agenda ou la salle d'attente.
class ConsultationCliniquePage extends StatelessWidget {
  final String? consultationId;

  const ConsultationCliniquePage({super.key, this.consultationId});

  @override
  Widget build(BuildContext context) {
    final bloc = GetIt.instance<ConsultationCliniqueBloc>();
    final id = consultationId;
    if (id != null) {
      bloc.add(ConsultationCliniqueLoadRequested(id));
    } else {
      bloc.add(const ConsultationHistoriqueRequested());
    }
    return BlocProvider.value(
      value: bloc,
      child: const _ConsultationCliniqueBody(),
    );
  }
}

// ---------------------------------------------------------------------------

class _ConsultationCliniqueBody extends StatelessWidget {
  const _ConsultationCliniqueBody();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ConsultationCliniqueBloc, ConsultationCliniqueState>(
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
          return const Center(
            key: Key('consultation_completed'),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle_outline, size: 64, color: Colors.green),
                SizedBox(height: 12),
                Text('Consultation terminée'),
              ],
            ),
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

class _LoadedView extends StatelessWidget {
  const _LoadedView({required this.state});
  final ConsultationCliniqueLoaded state;

  @override
  Widget build(BuildContext context) {
    final session = state.session;

    return Column(
      children: [
        if (state.actionInProgress)
          const LinearProgressIndicator(
              key: Key('consultation_action_progress')),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${session.acts.length} acte(s) CCAM',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              FilledButton.icon(
                key: const Key('complete_consultation_button'),
                onPressed: state.actionInProgress || session.isCompleted
                    ? null
                    : () => context.read<ConsultationCliniqueBloc>().add(
                          const ConsultationCliniqueCompleteRequested(),
                        ),
                icon: const Icon(Icons.check, size: 18),
                label: const Text('Terminer'),
              ),
            ],
          ),
        ),
        CcamPicker(
          key: const Key('ccam_picker'),
          useCase: const StubGetActsUseCase(),
          onActSelected: (act) =>
              context.read<ConsultationCliniqueBloc>().add(
                    ConsultationCliniqueActAddRequested(
                      ccamCode: act.code,
                      label: act.label,
                    ),
                  ),
        ),
        const Divider(height: 1),
        Expanded(
          child: session.acts.isEmpty
              ? const Center(
                  key: Key('consultation_empty'),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.medical_services_outlined, size: 48),
                      SizedBox(height: 12),
                      Text('Aucun acte enregistré'),
                    ],
                  ),
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

// ---------------------------------------------------------------------------

class _ActTile extends StatelessWidget {
  const _ActTile({required this.act});
  final ClinicalAct act;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      key: Key('act_${act.id}'),
      title: Text(act.label),
      subtitle: Text(act.ccamCode),
      trailing: act.amountCents != null
          ? Text(
              '${(act.amountCents! / 100).toStringAsFixed(2)} €',
              style: Theme.of(context).textTheme.bodyMedium,
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

  @override
  Widget build(BuildContext context) {
    return ListTile(
      key: Key('historique_${session.id}'),
      leading: const Icon(Icons.medical_services_outlined),
      title: Text('Consultation ${session.id}'),
      trailing: Chip(label: Text(_statusLabel)),
    );
  }
}

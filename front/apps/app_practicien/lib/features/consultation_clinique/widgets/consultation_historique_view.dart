// Quoi : vue « Historique » des consultations (filtre par statut + liste des
// séances passées/en cours/annulées).
// Quand : rendue par `ConsultationCliniqueBody` (`consultation_clinique_page.dart`)
// quand l'état du bloc est `ConsultationHistoriqueLoaded` (aucun
// `consultationId` fourni à l'écran).
// Pourquoi : extrait de `consultation_clinique_page.dart` (#4954) pour
// redescendre ce fichier sous le plafond de taille CLAUDE.md — aucun
// changement de rendu, mêmes Keys (`historique_filter`, `historique_empty`,
// `historique_list`, `historique_<id>`).
// Modes d'échec : #7033 — le segment sélectionné redemande la liste au
// serveur (`ConsultationHistoriqueRequested(status: …)`) au lieu de trier la
// seule page déjà chargée en mémoire ; `widget.sessions` reflète donc
// toujours le statut courant. Le tap sur une carte navigue via `go_router`
// (`AppRouter.consultation`).
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import '../../../router/app_router.dart';
import 'consultation_format_utils.dart';
import '../consultation_clinique_bloc.dart';
import '../consultation_clinique_event.dart';

class HistoriqueView extends StatefulWidget {
  const HistoriqueView(
      {super.key, required this.sessions, this.selectedStatus});
  final List<ClinicalSession> sessions;

  /// Statut courant de la requête serveur ayant produit [sessions] — permet
  /// de resynchroniser le segment sélectionné, la vue étant recréée à chaque
  /// changement d'état du bloc (#7033).
  final String? selectedStatus;

  @override
  State<HistoriqueView> createState() => _HistoriqueViewState();
}

class _HistoriqueViewState extends State<HistoriqueView> {
  late Set<String> _selection =
      widget.selectedStatus == null ? {} : {widget.selectedStatus!};

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

  void _onSelectionChanged(Set<String> s) {
    setState(() => _selection = s);
    context.read<ConsultationCliniqueBloc>().add(
          ConsultationHistoriqueRequested(status: s.isEmpty ? null : s.first),
        );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: SegmentedButton<String>(
            key: const Key('historique_filter'),
            segments: _segments,
            selected: _selection,
            onSelectionChanged: _onSelectionChanged,
            multiSelectionEnabled: false,
            emptySelectionAllowed: true,
          ),
        ),
        Expanded(
          child: widget.sessions.isEmpty
              ? const NubiaEmptyState(
                  key: Key('historique_empty'),
                  icon: Icons.medical_services_outlined,
                  title: 'Aucune consultation',
                )
              : ListView.builder(
                  key: const Key('historique_list'),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: widget.sessions.length,
                  itemBuilder: (_, i) =>
                      _HistoriqueTile(session: widget.sessions[i]),
                ),
        ),
      ],
    );
  }
}

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

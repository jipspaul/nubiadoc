import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import '../agenda/agenda_bloc.dart';
import '../agenda/agenda_state.dart';

/// Carte « Journée » (#5046, maquette design-v2 praticien) : déroule les RDV
/// du jour dans la colonne de gauche du tableau de bord — passés estompés,
/// courant teinté, à venir normaux — plutôt que de laisser la tuile
/// « RDV aujourd'hui » comme seul compteur (« la journée en clair, pas en
/// compteur »). Consomme [AgendaBloc], déjà chargé pour la semaine en cours
/// par l'appelant, et filtre sur la journée d'aujourd'hui.
class TodayScheduleCard extends StatelessWidget {
  const TodayScheduleCard({super.key, required this.summary});

  final ProDashboardSummary summary;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return BlocBuilder<AgendaBloc, AgendaState>(
      builder: (context, state) {
        final allEntries =
            state is AgendaLoaded ? state.entries : const <AgendaEntry>[];
        final today = _todayEntries(allEntries);
        final remaining = today.where((e) => !_isPast(e)).length;

        return NubiaCard(
          key: const Key('today_schedule_card'),
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                child: Row(
                  children: [
                    Icon(
                      Icons.calendar_today,
                      size: 20,
                      color: cs.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Journée',
                      style:
                          textTheme.titleMedium?.copyWith(color: cs.onSurface),
                    ),
                    const Spacer(),
                    StatusPill(
                      key: const Key('today_schedule_badge'),
                      label: '${summary.todayAppointments} RDV · '
                          '$remaining restants',
                      variant: StatusPillVariant.neutral,
                    ),
                  ],
                ),
              ),
              if (today.isEmpty)
                const Padding(
                  key: Key('today_schedule_empty'),
                  padding: EdgeInsets.only(bottom: 8),
                  child: NubiaEmptyState(
                    icon: Icons.calendar_today_outlined,
                    title: 'Aucun rendez-vous aujourd\'hui',
                  ),
                )
              else
                for (int i = 0; i < today.length; i++)
                  _ScheduleRow(
                    entry: today[i],
                    showDivider: i < today.length - 1,
                  ),
            ],
          ),
        );
      },
    );
  }

  List<AgendaEntry> _todayEntries(List<AgendaEntry> entries) {
    final now = DateTime.now();
    final result = entries
        .where((e) =>
            !e.isFree &&
            e.startsAt.year == now.year &&
            e.startsAt.month == now.month &&
            e.startsAt.day == now.day)
        .toList()
      ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
    return result;
  }
}

bool _isPast(AgendaEntry entry) => entry.endsAt.isBefore(DateTime.now());

bool _isNow(AgendaEntry entry) {
  final now = DateTime.now();
  return !entry.startsAt.isAfter(now) && entry.endsAt.isAfter(now);
}

class _ScheduleRow extends StatelessWidget {
  const _ScheduleRow({required this.entry, required this.showDivider});

  final AgendaEntry entry;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    final textTheme = Theme.of(context).textTheme;
    final style = ScheduleStatusStyle.of(entry);
    final past = _isPast(entry);
    final now = _isNow(entry);
    final hour = entry.startsAt.hour.toString().padLeft(2, '0');
    final minute = entry.startsAt.minute.toString().padLeft(2, '0');

    final row = ListRow(
      key: Key('today_schedule_row_${entry.id}'),
      leading: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$hour:$minute',
            style: textTheme.labelMedium?.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: 10),
          NubiaAvatar(initials: _initials(entry.patientName ?? '?')),
        ],
      ),
      title: entry.patientName ?? 'Patient',
      subtitle: entry.motif,
      trailing: StatusPill(label: style.label, variant: style.variant),
      showDivider: false,
    );

    return Opacity(
      opacity: past ? 0.55 : 1,
      child: Container(
        color: now ? tokens.primarySubtleBg : null,
        child: Column(
          children: [
            row,
            if (showDivider)
              Divider(height: 1, thickness: 1, color: tokens.borderSubtle),
          ],
        ),
      ),
    );
  }
}

/// Mapping du statut d'un [AgendaEntry] → libellé FR + variant [StatusPill],
/// à l'image de `NoteStatusStyle` (#5048) — la maquette design-v2 impose ses
/// propres libellés/couleurs pour la carte « Journée » (« Terminé » en vert,
/// « En attente » en info, « À venir » en gris neutre, « À confirmer » en
/// warning), distincts du vocabulaire de l'agenda hebdomadaire.
class ScheduleStatusStyle {
  const ScheduleStatusStyle(this.label, this.variant);

  final String label;
  final StatusPillVariant variant;

  static ScheduleStatusStyle of(AgendaEntry entry) {
    if (entry.isCancelled) {
      return const ScheduleStatusStyle('Annulé', StatusPillVariant.error);
    }
    if (entry.isNoShow) {
      return const ScheduleStatusStyle('Absent', StatusPillVariant.error);
    }
    if (entry.isDone) {
      return const ScheduleStatusStyle('Terminé', StatusPillVariant.success);
    }
    if (entry.isInProgress) {
      return const ScheduleStatusStyle('En cours', StatusPillVariant.progress);
    }
    if (entry.isCheckedIn) {
      return const ScheduleStatusStyle('En attente', StatusPillVariant.info);
    }
    if (entry.isConfirmed) {
      return const ScheduleStatusStyle('À venir', StatusPillVariant.neutral);
    }
    return const ScheduleStatusStyle('À confirmer', StatusPillVariant.warning);
  }
}

/// Initiales (max 2 lettres) à partir d'un nom complet.
String _initials(String fullName) {
  final parts = fullName
      .trim()
      .split(RegExp(r'\s+'))
      .where((p) => p.isNotEmpty)
      .toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
  return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
      .toUpperCase();
}

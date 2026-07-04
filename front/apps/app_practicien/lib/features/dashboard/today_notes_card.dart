import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'today_notes_bloc.dart';

/// Card displaying today's consultation notes.
/// Consumes [TodayNotesBloc] injected via BlocProvider.
class TodayNotesCard extends StatelessWidget {
  const TodayNotesCard({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<TodayNotesBloc, TodayNotesState>(
      builder: (context, state) {
        final cs = Theme.of(context).colorScheme;
        final textTheme = Theme.of(context).textTheme;
        final entries = switch (state) {
          TodayNotesLoaded(:final entries) => entries,
          _ => const <ClinicalNoteSummary>[],
        };

        return NubiaCard(
          key: const Key('today_notes_card'),
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
                      Icons.notes_outlined,
                      size: 20,
                      color: cs.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Notes du jour',
                      style: textTheme.titleMedium?.copyWith(
                        color: cs.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
              if (entries.isEmpty)
                const Padding(
                  key: Key('today_notes_empty'),
                  padding: EdgeInsets.only(bottom: 8),
                  child: NubiaEmptyState(
                    icon: Icons.event_available_outlined,
                    title: 'Aucune consultation aujourd\'hui',
                    subtitle: 'Les notes des consultations du jour '
                        'apparaîtront ici.',
                  ),
                )
              else
                for (int i = 0; i < entries.length; i++)
                  _NoteRow(
                    entry: entries[i],
                    showDivider: i < entries.length - 1,
                  ),
            ],
          ),
        );
      },
    );
  }
}

class _NoteRow extends StatelessWidget {
  const _NoteRow({required this.entry, required this.showDivider});

  final ClinicalNoteSummary entry;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final hour = entry.timestamp.hour.toString().padLeft(2, '0');
    final min = entry.timestamp.minute.toString().padLeft(2, '0');

    return ListRow(
      key: Key('today_note_${entry.id}'),
      leading: NubiaAvatar(initials: entry.patientInitials, radius: 16),
      title: '$hour:$min',
      subtitle: 'Consultation',
      trailing: StatusPill(
        label: entry.status,
        variant: _variantFor(entry.status),
      ),
      showDivider: showDivider,
    );
  }

  /// Traduit le statut textuel d'une note en variante sémantique de pill.
  StatusPillVariant _variantFor(String status) {
    final normalized = status.toLowerCase();
    if (normalized.contains('signé') ||
        normalized.contains('validé') ||
        normalized.contains('terminé') ||
        normalized.contains('clôturé')) {
      return StatusPillVariant.success;
    }
    if (normalized.contains('attente') ||
        normalized.contains('brouillon') ||
        normalized.contains('cours')) {
      return StatusPillVariant.warning;
    }
    if (normalized.contains('annulé') || normalized.contains('erreur')) {
      return StatusPillVariant.error;
    }
    return StatusPillVariant.info;
  }
}

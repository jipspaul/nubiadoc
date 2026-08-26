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
    final style = NoteStatusStyle.of(entry.status);

    return ListRow(
      key: Key('today_note_${entry.id}'),
      leading: NubiaAvatar(initials: entry.patientInitials, radius: 16),
      title: '$hour:$min',
      subtitle: 'Consultation',
      trailing: StatusPill(
        label: style.label,
        variant: style.variant,
      ),
      showDivider: showDivider,
    );
  }
}

/// Mapping statut de note → libellé FR + variant [StatusPill], à l'image de
/// `QuoteStatusStyle` (#5054). Table de correspondance explicite — remplace
/// l'ancien `_variantFor` (mapping par sous-chaîne `String.contains`, qui
/// classait « Non signée » en succès car `contains('signé')` matchait aussi
/// la négation).
///
/// Clé sur `String` (pas encore l'énum domaine `ClinicalNoteStatus`, qui
/// dépend d'un ticket domaine séparé non disponible à date).
class NoteStatusStyle {
  const NoteStatusStyle(this.label, this.variant);

  final String label;
  final StatusPillVariant variant;

  static NoteStatusStyle of(String status) => switch (status) {
        'Signée' || 'Signé' || 'Terminée' =>
          NoteStatusStyle(status, StatusPillVariant.success),
        'Brouillon' || 'En cours' || 'En attente' =>
          NoteStatusStyle(status, StatusPillVariant.warning),
        'Non signée' || 'Non signé' || 'Annulée' || 'Annulé' =>
          NoteStatusStyle(status, StatusPillVariant.error),
        _ => NoteStatusStyle(status, StatusPillVariant.info),
      };
}

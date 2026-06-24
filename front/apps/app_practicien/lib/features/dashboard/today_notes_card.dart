import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'today_notes_bloc.dart';

/// Card displaying the last 3 consultations of the day.
/// Consumes [TodayNotesBloc] injected via BlocProvider.
class TodayNotesCard extends StatelessWidget {
  const TodayNotesCard({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<TodayNotesBloc, TodayNotesState>(
      builder: (context, state) {
        final entries = switch (state) {
          TodayNotesLoaded(:final entries) => entries,
          _ => const <TodayNoteEntry>[],
        };

        return Card(
          key: const Key('today_notes_card'),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Icon(Icons.notes_outlined, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Notes du jour',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (entries.isEmpty)
                  const Center(
                    key: Key('today_notes_empty'),
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text('Aucune consultation aujourd\'hui'),
                    ),
                  )
                else
                  ...entries.map((e) => _NoteRow(entry: e)),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _NoteRow extends StatelessWidget {
  const _NoteRow({required this.entry});

  final TodayNoteEntry entry;

  @override
  Widget build(BuildContext context) {
    final hour = entry.timestamp.hour.toString().padLeft(2, '0');
    final min = entry.timestamp.minute.toString().padLeft(2, '0');

    return ListTile(
      key: Key('today_note_${entry.id}'),
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        radius: 16,
        child: Text(
          entry.patientInitials,
          style: const TextStyle(fontSize: 12),
        ),
      ),
      title: Text('$hour:$min'),
      trailing: Chip(
        label: Text(entry.status),
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

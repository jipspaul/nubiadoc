import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import '../../router/app_router.dart';
import 'tasks_bloc.dart';
import 'tasks_event.dart';
import 'tasks_state.dart';
import 'widgets/task_row.dart';

/// Carte « Tâches » du tableau de bord (#7210) : file des tâches ouvertes
/// (assignées à moi ou au cabinet selon le filtre du [TasksBloc] fourni par
/// l'appelant), clôture en un tap, lien vers l'écran Tâches complet.
class TasksCard extends StatelessWidget {
  const TasksCard({super.key});

  /// Nombre de lignes affichées avant de renvoyer vers l'écran complet.
  static const int _maxRows = 5;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return NubiaCard(
      key: const Key('tasks_card'),
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
                  Icons.checklist_outlined,
                  size: 20,
                  color: cs.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Text(
                  'Tâches',
                  style: textTheme.titleMedium?.copyWith(color: cs.onSurface),
                ),
                const Spacer(),
                TextButton(
                  key: const Key('tasks_card_see_all'),
                  onPressed: () => context.push(AppRouter.tasks),
                  child: const Text('Voir tout'),
                ),
              ],
            ),
          ),
          BlocBuilder<TasksBloc, TasksState>(
            builder: (context, state) {
              return switch (state) {
                TasksInitial() || TasksLoading() => const Padding(
                    key: Key('tasks_card_loading'),
                    padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: NubiaSkeletonLoader(height: 64, borderRadius: 8),
                  ),
                TasksError(:final message) => Padding(
                    key: const Key('tasks_card_error'),
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Text(
                      message,
                      style: TextStyle(color: cs.error),
                    ),
                  ),
                TasksLoaded(:final tasks) when tasks.isEmpty => Padding(
                    key: const Key('tasks_card_empty'),
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Text(
                      'Aucune tâche en cours.',
                      style: textTheme.bodyMedium
                          ?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ),
                TasksLoaded(:final tasks) => _TaskRows(
                    tasks: tasks.take(_maxRows).toList(),
                  ),
              };
            },
          ),
        ],
      ),
    );
  }
}

class _TaskRows extends StatelessWidget {
  const _TaskRows({required this.tasks});

  final List<CabinetTask> tasks;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (i, task) in tasks.indexed)
          TaskRow(
            task: task,
            showDivider: i < tasks.length - 1,
            onComplete: () =>
                context.read<TasksBloc>().add(TasksCompleteRequested(task.id)),
          ),
      ],
    );
  }
}

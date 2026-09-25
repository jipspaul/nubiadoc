import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import '../../router/back_or_home_leading.dart';
import '../../session/pro_auth_cubit.dart';
import 'tasks_bloc.dart';
import 'tasks_event.dart';
import 'tasks_state.dart';
import 'widgets/task_row.dart';

/// Écran « Tâches » (#7210) : file des tâches actives/historique du
/// cabinet, filtre assigné, création rapide, clôture en un tap.
class TasksPage extends StatelessWidget {
  const TasksPage({super.key});

  @override
  Widget build(BuildContext context) {
    final myUserId = switch (context.watch<ProAuthCubit>().state) {
      AuthAuthenticated(:final session) => session.userId,
      _ => null,
    };
    return BlocProvider(
      create: (_) => GetIt.instance<TasksBloc>()
        ..add(TasksLoadRequested(assigneeId: myUserId, status: 'open')),
      child: _TasksView(myUserId: myUserId),
    );
  }
}

class _TasksView extends StatefulWidget {
  const _TasksView({required this.myUserId});

  final String? myUserId;

  @override
  State<_TasksView> createState() => _TasksViewState();
}

class _TasksViewState extends State<_TasksView> {
  bool _showHistory = false;
  bool _onlyMine = true;

  @override
  void didUpdateWidget(covariant _TasksView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // La session (ProAuthCubit) peut devenir disponible après le premier
    // build : le `create:` du BlocProvider parent n'est pas rejoué, il faut
    // donc redemander explicitement avec le bon assigneeId.
    if (oldWidget.myUserId != widget.myUserId) {
      _reload(context);
    }
  }

  void _reload(BuildContext context) {
    context.read<TasksBloc>().add(TasksLoadRequested(
          assigneeId: _onlyMine ? widget.myUserId : null,
          status: _showHistory ? 'done' : 'open',
        ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: backOrHomeLeading(context),
        title: const Text('Tâches'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('tasks_create_fab'),
        onPressed: () => showDialog<void>(
          context: context,
          builder: (_) => BlocProvider.value(
            value: context.read<TasksBloc>(),
            child: const _CreateTaskDialog(),
          ),
        ),
        icon: const Icon(Icons.add),
        label: const Text('Nouvelle tâche'),
      ),
      body: BlocListener<TasksBloc, TasksState>(
        listenWhen: (_, current) =>
            current is TasksLoaded && current.actionError != null,
        listener: (context, state) {
          if (state is TasksLoaded && state.actionError != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(state.actionError!)),
            );
          }
        },
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    key: const Key('tasks_filter_active'),
                    label: const Text('Actives'),
                    selected: !_showHistory,
                    onSelected: (_) {
                      setState(() => _showHistory = false);
                      _reload(context);
                    },
                  ),
                  ChoiceChip(
                    key: const Key('tasks_filter_history'),
                    label: const Text('Historique'),
                    selected: _showHistory,
                    onSelected: (_) {
                      setState(() => _showHistory = true);
                      _reload(context);
                    },
                  ),
                  if (widget.myUserId != null)
                    FilterChip(
                      key: const Key('tasks_filter_mine'),
                      label: const Text('Assignées à moi'),
                      selected: _onlyMine,
                      onSelected: (selected) {
                        setState(() => _onlyMine = selected);
                        _reload(context);
                      },
                    ),
                ],
              ),
            ),
            Expanded(
              child: BlocBuilder<TasksBloc, TasksState>(
                builder: (context, state) {
                  return switch (state) {
                    TasksInitial() || TasksLoading() => const Center(
                        key: Key('tasks_page_loading'),
                        child: CircularProgressIndicator(),
                      ),
                    TasksError(:final message) => NubiaErrorWidget(
                        key: const Key('tasks_page_error'),
                        message: message,
                        onRetry: () => _reload(context),
                      ),
                    TasksLoaded(:final tasks) when tasks.isEmpty =>
                      const NubiaEmptyState(
                        key: Key('tasks_page_empty'),
                        icon: Icons.checklist_outlined,
                        title: 'Aucune tâche',
                        subtitle: 'Aucune tâche ne correspond à ce filtre.',
                      ),
                    TasksLoaded(:final tasks) => ListView.builder(
                        key: const Key('tasks_page_list'),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: tasks.length,
                        itemBuilder: (_, i) => TaskRow(
                          task: tasks[i],
                          onComplete: () => context
                              .read<TasksBloc>()
                              .add(TasksCompleteRequested(tasks[i].id)),
                        ),
                      ),
                  };
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Dialogue de création rapide (#7210) : titre + assigné optionnel (membre
/// du cabinet) + échéance optionnelle.
class _CreateTaskDialog extends StatefulWidget {
  const _CreateTaskDialog();

  @override
  State<_CreateTaskDialog> createState() => _CreateTaskDialogState();
}

class _CreateTaskDialogState extends State<_CreateTaskDialog> {
  final _titleCtrl = TextEditingController();
  DateTime? _dueDate;
  Member? _assignee;
  List<Member> _members = const [];
  bool _loadingMembers = true;

  @override
  void initState() {
    super.initState();
    _loadMembers();
  }

  Future<void> _loadMembers() async {
    final result = await GetIt.instance<ListMembersUseCase>()();
    if (!mounted) return;
    result.fold(
      (_) => setState(() => _loadingMembers = false),
      (members) => setState(() {
        _members = members;
        _loadingMembers = false;
      }),
    );
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canCreate = _titleCtrl.text.trim().isNotEmpty;
    return AlertDialog(
      title: const Text('Nouvelle tâche'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const Key('task_title_field'),
              controller: _titleCtrl,
              decoration: const InputDecoration(labelText: 'Titre *'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            if (_loadingMembers)
              const LinearProgressIndicator(key: Key('task_members_loading'))
            else
              InputDecorator(
                decoration: const InputDecoration(labelText: 'Assigné à'),
                child: DropdownButton<Member?>(
                  key: const Key('task_assignee_dropdown'),
                  isExpanded: true,
                  underline: const SizedBox.shrink(),
                  value: _assignee,
                  hint: const Text('Personne (optionnel)'),
                  items: [
                    const DropdownMenuItem<Member?>(
                      value: null,
                      child: Text('Personne (optionnel)'),
                    ),
                    for (final member in _members)
                      DropdownMenuItem<Member?>(
                        value: member,
                        child: Text(member.fullName),
                      ),
                  ],
                  onChanged: (m) => setState(() => _assignee = m),
                ),
              ),
            const SizedBox(height: 12),
            InkWell(
              key: const Key('task_due_date_picker'),
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _dueDate ?? DateTime.now(),
                  firstDate: DateTime.now().subtract(const Duration(days: 1)),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                );
                if (picked != null) setState(() => _dueDate = picked);
              },
              child: InputDecorator(
                decoration: const InputDecoration(labelText: 'Échéance'),
                child: Text(
                  _dueDate == null
                      ? 'Aucune échéance'
                      : '${_dueDate!.year}-${_dueDate!.month.toString().padLeft(2, '0')}-${_dueDate!.day.toString().padLeft(2, '0')}',
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(
          key: const Key('task_create_confirm'),
          onPressed: canCreate
              ? () {
                  final due = _dueDate;
                  context.read<TasksBloc>().add(TasksCreateRequested(
                        title: _titleCtrl.text.trim(),
                        assigneeUserId: _assignee?.id,
                        dueDate: due == null
                            ? null
                            : '${due.year}-${due.month.toString().padLeft(2, '0')}-${due.day.toString().padLeft(2, '0')}',
                      ));
                  Navigator.of(context).pop();
                }
              : null,
          child: const Text('Créer'),
        ),
      ],
    );
  }
}

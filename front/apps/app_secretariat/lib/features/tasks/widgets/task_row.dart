import 'package:flutter/material.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

/// Ligne d'une tâche : case à cocher pour clôturer en un tap (#7210),
/// titre, et sous-titre récapitulant assigné/patient/échéance.
class TaskRow extends StatelessWidget {
  const TaskRow({
    super.key,
    required this.task,
    this.onComplete,
    this.showDivider = true,
  });

  final CabinetTask task;
  final VoidCallback? onComplete;
  final bool showDivider;

  String? get _subtitle {
    final parts = <String>[
      if (task.assigneeDisplayName != null) 'Pour ${task.assigneeDisplayName}',
      if (task.patientDisplayName != null) task.patientDisplayName!,
      if (task.dueDate != null) 'Échéance ${task.dueDate}',
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    return ListRow(
      key: Key('task_row_${task.id}'),
      title: task.title,
      subtitle: _subtitle,
      leading: NubiaCheckbox(
        key: Key('task_checkbox_${task.id}'),
        value: task.isDone,
        onChanged:
            task.isOpen && onComplete != null ? (_) => onComplete!() : null,
      ),
      showDivider: showDivider,
    );
  }
}

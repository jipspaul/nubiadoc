import 'package:equatable/equatable.dart';

sealed class TasksEvent extends Equatable {
  const TasksEvent();

  @override
  List<Object?> get props => [];
}

/// Charge les tâches du cabinet, filtrable par assigné (`null` = tout le
/// cabinet) et par statut (`null` = tous statuts confondus).
class TasksLoadRequested extends TasksEvent {
  const TasksLoadRequested({this.assigneeId, this.status});

  final String? assigneeId;
  final String? status;

  @override
  List<Object?> get props => [assigneeId, status];
}

/// Clôture une tâche en un tap (#7210).
class TasksCompleteRequested extends TasksEvent {
  const TasksCompleteRequested(this.taskId);

  final String taskId;

  @override
  List<Object?> get props => [taskId];
}

/// Création rapide d'une tâche depuis l'écran Tâches.
class TasksCreateRequested extends TasksEvent {
  const TasksCreateRequested({
    required this.title,
    this.description,
    this.assigneeUserId,
    this.dueDate,
  });

  final String title;
  final String? description;
  final String? assigneeUserId;

  /// Date ISO `YYYY-MM-DD`.
  final String? dueDate;

  @override
  List<Object?> get props => [title, description, assigneeUserId, dueDate];
}

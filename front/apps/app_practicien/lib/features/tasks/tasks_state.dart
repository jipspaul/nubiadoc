import 'package:equatable/equatable.dart';
import 'package:nubia_domain/nubia_domain.dart';

sealed class TasksState extends Equatable {
  const TasksState();

  @override
  List<Object?> get props => [];
}

class TasksInitial extends TasksState {
  const TasksInitial();
}

class TasksLoading extends TasksState {
  const TasksLoading();
}

class TasksError extends TasksState {
  const TasksError(this.message);

  final String message;

  @override
  List<Object?> get props => [message];
}

class TasksLoaded extends TasksState {
  const TasksLoaded({
    required this.tasks,
    this.assigneeId,
    this.status,
    this.actionInProgress = false,
    this.actionError,
  });

  final List<CabinetTask> tasks;

  /// Filtre courant (conservé pour recharger après une action).
  final String? assigneeId;
  final String? status;

  final bool actionInProgress;
  final String? actionError;

  TasksLoaded copyWith({
    List<CabinetTask>? tasks,
    bool? actionInProgress,
    String? actionError,
    bool clearActionError = false,
  }) =>
      TasksLoaded(
        tasks: tasks ?? this.tasks,
        assigneeId: assigneeId,
        status: status,
        actionInProgress: actionInProgress ?? this.actionInProgress,
        actionError:
            clearActionError ? null : (actionError ?? this.actionError),
      );

  @override
  List<Object?> get props =>
      [tasks, assigneeId, status, actionInProgress, actionError];
}

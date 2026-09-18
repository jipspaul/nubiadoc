import 'package:bloc/bloc.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'tasks_event.dart';
import 'tasks_state.dart';

/// Tâches du cabinet (#7210) : liste filtrable (assigné/statut), création
/// rapide, clôture en un tap.
class TasksBloc extends Bloc<TasksEvent, TasksState>
    with SafeEmitMixin<TasksState> {
  TasksBloc({
    required ListCabinetTasksUseCase listTasks,
    required CreateCabinetTaskUseCase createTask,
    required CompleteCabinetTaskUseCase completeTask,
  })  : _listTasks = listTasks,
        _createTask = createTask,
        _completeTask = completeTask,
        super(const TasksInitial()) {
    on<TasksLoadRequested>(_onLoad);
    on<TasksCompleteRequested>(_onComplete);
    on<TasksCreateRequested>(_onCreate);
  }

  final ListCabinetTasksUseCase _listTasks;
  final CreateCabinetTaskUseCase _createTask;
  final CompleteCabinetTaskUseCase _completeTask;

  Future<void> _onLoad(
    TasksLoadRequested event,
    Emitter<TasksState> emit,
  ) async {
    emit(const TasksLoading());
    final result = await _listTasks(
      assigneeId: event.assigneeId,
      status: event.status,
    );
    result.fold(
      (failure) => safeEmit(TasksError(failure.message)),
      (tasks) => safeEmit(TasksLoaded(
        tasks: tasks,
        assigneeId: event.assigneeId,
        status: event.status,
      )),
    );
  }

  Future<void> _onComplete(
    TasksCompleteRequested event,
    Emitter<TasksState> emit,
  ) async {
    final current = state;
    if (current is! TasksLoaded) return;
    emit(current.copyWith(actionInProgress: true, clearActionError: true));
    final result = await _completeTask(event.taskId);
    result.fold(
      (failure) => safeEmit(current.copyWith(
        actionInProgress: false,
        actionError: failure.message,
      )),
      (_) => add(TasksLoadRequested(
        assigneeId: current.assigneeId,
        status: current.status,
      )),
    );
  }

  Future<void> _onCreate(
    TasksCreateRequested event,
    Emitter<TasksState> emit,
  ) async {
    final current = state;
    if (current is! TasksLoaded) return;
    emit(current.copyWith(actionInProgress: true, clearActionError: true));
    final result = await _createTask(
      title: event.title,
      description: event.description,
      assigneeUserId: event.assigneeUserId,
      dueDate: event.dueDate,
    );
    result.fold(
      (failure) => safeEmit(current.copyWith(
        actionInProgress: false,
        actionError: failure.message,
      )),
      (_) => add(TasksLoadRequested(
        assigneeId: current.assigneeId,
        status: current.status,
      )),
    );
  }
}

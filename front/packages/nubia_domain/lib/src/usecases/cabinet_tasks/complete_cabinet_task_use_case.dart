import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/cabinet_tasks_repository.dart';

/// Clôture une tâche en un tap (#7210) — `POST /v1/cabinet/tasks/:id/complete`.
class CompleteCabinetTaskUseCase {
  final CabinetTasksRepository _repository;

  const CompleteCabinetTaskUseCase(this._repository);

  Future<Either<Failure, String>> call(String taskId) =>
      _repository.complete(taskId);
}

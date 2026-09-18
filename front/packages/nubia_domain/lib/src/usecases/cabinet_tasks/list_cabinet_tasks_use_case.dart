import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/cabinet_task.dart';
import 'package:nubia_domain/src/repositories/cabinet_tasks_repository.dart';

class ListCabinetTasksUseCase {
  final CabinetTasksRepository _repository;

  const ListCabinetTasksUseCase(this._repository);

  Future<Either<Failure, List<CabinetTask>>> call({
    String? assigneeId,
    String? status,
  }) =>
      _repository.list(assigneeId: assigneeId, status: status);
}

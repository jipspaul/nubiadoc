import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/cabinet_tasks_repository.dart';

class CreateCabinetTaskUseCase {
  final CabinetTasksRepository _repository;

  const CreateCabinetTaskUseCase(this._repository);

  Future<Either<Failure, String>> call({
    required String title,
    String? description,
    String? assigneeUserId,
    String? patientId,
    String? appointmentId,
    String? dueDate,
  }) =>
      _repository.create(
        title: title,
        description: description,
        assigneeUserId: assigneeUserId,
        patientId: patientId,
        appointmentId: appointmentId,
        dueDate: dueDate,
      );
}

import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/cabinet_tasks_repository.dart';

/// Raccourci « tâche pour l'assistante » posée depuis le formulaire de
/// création de RDV secrétariat (#7210) — `POST /v1/appointments/:id/tasks`.
class CreateAppointmentTaskUseCase {
  final CabinetTasksRepository _repository;

  const CreateAppointmentTaskUseCase(this._repository);

  Future<Either<Failure, String>> call({
    required String appointmentId,
    required String title,
    String? description,
    String? assigneeUserId,
    String? dueDate,
  }) =>
      _repository.createForAppointment(
        appointmentId: appointmentId,
        title: title,
        description: description,
        assigneeUserId: assigneeUserId,
        dueDate: dueDate,
      );
}

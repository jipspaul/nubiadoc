import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/cabinet_task.dart';

abstract class CabinetTasksRepository {
  /// GET /v1/cabinet/tasks (#7211), filtrable par assigné/statut.
  Future<Either<Failure, List<CabinetTask>>> list({
    String? assigneeId,
    String? status,
  });

  /// POST /v1/cabinet/tasks (#7211). Renvoie l'id de la tâche créée.
  Future<Either<Failure, String>> create({
    required String title,
    String? description,
    String? assigneeUserId,
    String? patientId,
    String? appointmentId,
    String? dueDate,
  });

  /// POST /v1/appointments/:id/tasks (#7211) — raccourci « tâche pour
  /// l'assistante » depuis un RDV, patient/RDV pré-remplis côté back.
  /// Renvoie l'id de la tâche créée.
  Future<Either<Failure, String>> createForAppointment({
    required String appointmentId,
    required String title,
    String? description,
    String? assigneeUserId,
    String? dueDate,
  });

  /// POST /v1/cabinet/tasks/:id/complete (#7211). Renvoie le nouveau statut.
  Future<Either<Failure, String>> complete(String taskId);
}

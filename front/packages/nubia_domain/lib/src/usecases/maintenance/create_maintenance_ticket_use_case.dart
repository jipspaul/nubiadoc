import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/maintenance_ticket.dart';
import 'package:nubia_domain/src/repositories/maintenance_repository.dart';

class CreateMaintenanceTicketUseCase {
  final MaintenanceRepository _repository;

  const CreateMaintenanceTicketUseCase(this._repository);

  Future<Either<Failure, MaintenanceTicket>> call({
    String? equipmentId,
    required String title,
    String? description,
    String? priority,
    String? assignedToEmail,
    List<String> photoDocumentIds = const [],
  }) =>
      _repository.createTicket(
        equipmentId: equipmentId,
        title: title,
        description: description,
        priority: priority,
        assignedToEmail: assignedToEmail,
        photoDocumentIds: photoDocumentIds,
      );
}

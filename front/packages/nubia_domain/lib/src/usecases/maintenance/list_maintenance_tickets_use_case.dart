import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/maintenance_ticket.dart';
import 'package:nubia_domain/src/repositories/maintenance_repository.dart';

class ListMaintenanceTicketsUseCase {
  final MaintenanceRepository _repository;

  const ListMaintenanceTicketsUseCase(this._repository);

  Future<Either<Failure, List<MaintenanceTicket>>> call({
    String? status,
    String? equipmentId,
  }) =>
      _repository.listTickets(status: status, equipmentId: equipmentId);
}

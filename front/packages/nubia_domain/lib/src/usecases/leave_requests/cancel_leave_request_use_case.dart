import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/leave_request.dart';
import 'package:nubia_domain/src/repositories/leave_requests_repository.dart';

/// Annulation par le demandeur de sa propre demande de congé (#7143/#7144).
class CancelLeaveRequestUseCase {
  final LeaveRequestsRepository _repository;

  const CancelLeaveRequestUseCase(this._repository);

  Future<Either<Failure, LeaveRequest>> call(String id) =>
      _repository.cancel(id);
}

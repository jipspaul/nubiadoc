import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/leave_request.dart';
import 'package:nubia_domain/src/repositories/leave_requests_repository.dart';

/// Validation manager d'une demande de congé (#7143/#7144), réservée
/// admin/manager côté back.
class DecideLeaveRequestUseCase {
  final LeaveRequestsRepository _repository;

  const DecideLeaveRequestUseCase(this._repository);

  Future<Either<Failure, LeaveRequest>> call({
    required String id,
    required bool approve,
  }) =>
      _repository.decide(id: id, approve: approve);
}

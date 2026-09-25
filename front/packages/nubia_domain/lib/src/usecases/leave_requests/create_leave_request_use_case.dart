import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/leave_request.dart';
import 'package:nubia_domain/src/repositories/leave_requests_repository.dart';

/// Demande de congé pour soi-même (#7143/#7144).
class CreateLeaveRequestUseCase {
  final LeaveRequestsRepository _repository;

  const CreateLeaveRequestUseCase(this._repository);

  Future<Either<Failure, LeaveRequest>> call({
    required String startsAt,
    required String endsAt,
    required String kind,
  }) =>
      _repository.create(startsAt: startsAt, endsAt: endsAt, kind: kind);
}

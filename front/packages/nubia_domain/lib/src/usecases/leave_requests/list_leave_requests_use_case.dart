import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/leave_request.dart';
import 'package:nubia_domain/src/repositories/leave_requests_repository.dart';

class ListLeaveRequestsUseCase {
  final LeaveRequestsRepository _repository;

  const ListLeaveRequestsUseCase(this._repository);

  Future<Either<Failure, List<LeaveRequest>>> call({
    String? userId,
    String? status,
  }) =>
      _repository.list(userId: userId, status: status);
}

import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/lab_work_orders_repository.dart';

class UpdateLabWorkOrderStatusUseCase {
  final LabWorkOrdersRepository _repository;

  const UpdateLabWorkOrderStatusUseCase(this._repository);

  Future<Either<Failure, String>> call(String orderId, String status) =>
      _repository.updateStatus(orderId, status);
}

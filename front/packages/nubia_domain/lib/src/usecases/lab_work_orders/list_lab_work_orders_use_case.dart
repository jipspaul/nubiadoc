import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/lab_work_order.dart';
import 'package:nubia_domain/src/repositories/lab_work_orders_repository.dart';

class ListLabWorkOrdersUseCase {
  final LabWorkOrdersRepository _repository;

  const ListLabWorkOrdersUseCase(this._repository);

  Future<Either<Failure, List<LabWorkOrder>>> call() =>
      _repository.listOrders();
}

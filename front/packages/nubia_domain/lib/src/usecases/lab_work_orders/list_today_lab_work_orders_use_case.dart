import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/today_lab_work_order.dart';
import 'package:nubia_domain/src/repositories/lab_work_orders_repository.dart';

class ListTodayLabWorkOrdersUseCase {
  final LabWorkOrdersRepository _repository;

  const ListTodayLabWorkOrdersUseCase(this._repository);

  Future<Either<Failure, List<TodayLabWorkOrder>>> call() =>
      _repository.todayOrders();
}

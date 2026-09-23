import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/lab_price_list_item.dart';
import 'package:nubia_domain/src/repositories/lab_work_orders_repository.dart';

class ListLabPriceListUseCase {
  final LabWorkOrdersRepository _repository;

  const ListLabPriceListUseCase(this._repository);

  Future<Either<Failure, List<LabPriceListItem>>> call() =>
      _repository.listPriceList();
}

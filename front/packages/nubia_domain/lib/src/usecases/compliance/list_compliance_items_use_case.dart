import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/entities/compliance_item.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/compliance_repository.dart';

class ListComplianceItemsUseCase {
  final ComplianceRepository _repository;

  const ListComplianceItemsUseCase(this._repository);

  Future<Either<Failure, List<ComplianceItem>>> call() =>
      _repository.listItems();
}

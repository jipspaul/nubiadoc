import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/equipment.dart';
import 'package:nubia_domain/src/repositories/maintenance_repository.dart';

class ListEquipmentUseCase {
  final MaintenanceRepository _repository;

  const ListEquipmentUseCase(this._repository);

  Future<Either<Failure, List<Equipment>>> call() =>
      _repository.listEquipment();
}

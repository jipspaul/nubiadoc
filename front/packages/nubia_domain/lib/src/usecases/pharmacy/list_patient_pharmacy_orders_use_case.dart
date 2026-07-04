import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/entities/pharmacy_order.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/patient_pharmacy_repository.dart';

class ListPatientPharmacyOrdersUseCase {
  final PatientPharmacyRepository _repository;

  const ListPatientPharmacyOrdersUseCase(this._repository);

  Future<Either<Failure, List<PharmacyOrder>>> call() =>
      _repository.listOrders();
}

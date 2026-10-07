import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/entities/pharmacy_order.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/patient_pharmacy_repository.dart';

class GetPatientPharmacyOrderUseCase {
  final PatientPharmacyRepository _repository;

  const GetPatientPharmacyOrderUseCase(this._repository);

  Future<Either<Failure, PharmacyOrder>> call(
    String id, {
    double? lat,
    double? lng,
  }) =>
      _repository.getOrder(id, lat: lat, lng: lng);
}

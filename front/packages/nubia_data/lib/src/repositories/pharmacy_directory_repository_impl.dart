import 'package:dartz/dartz.dart';
import 'package:nubia_data/src/remote/pharmacy_directory/pharmacy_directory_api.dart';
import 'package:nubia_data/src/repositories/pharmacy_failure_mapper.dart';
import 'package:nubia_domain/src/entities/pharmacy.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/pharmacy_directory_repository.dart';

class PharmacyDirectoryRepositoryImpl implements PharmacyDirectoryRepository {
  final PharmacyDirectoryApi _api;

  const PharmacyDirectoryRepositoryImpl(this._api);

  @override
  Future<Either<Failure, List<Pharmacy>>> search({
    String? query,
    double? lat,
    double? lng,
    double? radiusKm,
  }) =>
      guardPharmacyCall(
        () async {
          final dtos = await _api.search(
            query: query,
            lat: lat,
            lng: lng,
            radiusKm: radiusKm,
          );
          return dtos.map((dto) => dto.toDomain()).toList();
        },
        errorMessage: 'Impossible de rechercher les pharmacies.',
      );

  @override
  Future<Either<Failure, Pharmacy?>> getPatientPharmacy(String patientId) =>
      guardPharmacyCall(
        () async {
          final dto = await _api.getPatientPharmacy(patientId);
          return dto?.toDomain();
        },
        errorMessage: 'Impossible de charger la pharmacie du patient.',
      );
}

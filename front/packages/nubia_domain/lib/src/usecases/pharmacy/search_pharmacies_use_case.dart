import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/entities/pharmacy.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/pharmacy_directory_repository.dart';

class SearchPharmaciesUseCase {
  final PharmacyDirectoryRepository _repository;

  const SearchPharmaciesUseCase(this._repository);

  Future<Either<Failure, List<Pharmacy>>> call({
    String? query,
    double? lat,
    double? lng,
    double? radiusKm,
  }) =>
      _repository.search(query: query, lat: lat, lng: lng, radiusKm: radiusKm);
}

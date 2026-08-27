import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/entities/medication_reference.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/medication_reference_repository.dart';

class SearchMedicationReferencesUseCase {
  final MedicationReferenceRepository _repository;

  const SearchMedicationReferencesUseCase(this._repository);

  Future<Either<Failure, List<MedicationReference>>> call({
    required String query,
  }) =>
      _repository.searchMedicationReferences(query: query);
}

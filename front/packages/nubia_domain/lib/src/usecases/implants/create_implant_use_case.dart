import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/implant_item.dart';
import 'package:nubia_domain/src/repositories/implant_passport_repository.dart';

class CreateImplantUseCase {
  final ImplantPassportRepository _repository;

  const CreateImplantUseCase(this._repository);

  Future<Either<Failure, ImplantItem>> call({
    required String patientId,
    required String brand,
    required String implantRef,
    String? lotNumber,
    String? placementDate,
    String? toothPosition,
    String? notes,
    String? manufacturer,
    String? model,
    String? dimensions,
    String? material,
    String? mriCompatibility,
  }) =>
      _repository.createImplant(
        patientId: patientId,
        brand: brand,
        implantRef: implantRef,
        lotNumber: lotNumber,
        placementDate: placementDate,
        toothPosition: toothPosition,
        notes: notes,
        manufacturer: manufacturer,
        model: model,
        dimensions: dimensions,
        material: material,
        mriCompatibility: mriCompatibility,
      );
}

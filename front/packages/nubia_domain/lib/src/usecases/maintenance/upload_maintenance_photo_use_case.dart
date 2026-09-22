import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/maintenance_repository.dart';

class UploadMaintenancePhotoUseCase {
  final MaintenanceRepository _repository;

  const UploadMaintenancePhotoUseCase(this._repository);

  Future<Either<Failure, String>> call({
    required List<int> bytes,
    required String filename,
    required String mimeType,
  }) =>
      _repository.uploadPhoto(
        bytes: bytes,
        filename: filename,
        mimeType: mimeType,
      );
}

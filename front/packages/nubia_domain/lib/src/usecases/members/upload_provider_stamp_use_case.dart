import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/provider_stamp_repository.dart';

class UploadProviderStampUseCase {
  final ProviderStampRepository _repository;

  const UploadProviderStampUseCase(this._repository);

  Future<Either<Failure, String>> call({
    required List<int> bytes,
    required String filename,
    required String mimeType,
  }) =>
      _repository.uploadStamp(
        bytes: bytes,
        filename: filename,
        mimeType: mimeType,
      );
}

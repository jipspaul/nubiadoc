import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/provider_stamp_repository.dart';

class UploadProviderSignatureUseCase {
  final ProviderStampRepository _repository;

  const UploadProviderSignatureUseCase(this._repository);

  Future<Either<Failure, String>> call({
    required List<int> bytes,
    required String filename,
    required String mimeType,
  }) =>
      _repository.uploadSignature(
        bytes: bytes,
        filename: filename,
        mimeType: mimeType,
      );
}

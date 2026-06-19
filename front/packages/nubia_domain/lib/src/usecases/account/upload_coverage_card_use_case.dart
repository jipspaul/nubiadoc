import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/account_repository.dart';

class UploadCoverageCardUseCase {
  final AccountRepository _repository;

  const UploadCoverageCardUseCase(this._repository);

  /// Uploads [filePath] as a coverage card image.
  ///
  /// Returns the created `document_id` on success.
  Future<Either<Failure, String>> call({
    required String filePath,
    required String mimeType,
    required CoverageCardSide side,
  }) {
    return _repository.uploadCoverageCard(
      filePath: filePath,
      mimeType: mimeType,
      side: side,
    );
  }
}

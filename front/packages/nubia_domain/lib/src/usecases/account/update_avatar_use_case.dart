import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/account_repository.dart';

class UpdateAvatarUseCase {
  final AccountRepository _repository;
  const UpdateAvatarUseCase(this._repository);

  Future<Either<Failure, void>> call({
    required List<int> bytes,
    required String mimeType,
  }) =>
      _repository.setAvatar(bytes: bytes, mimeType: mimeType);
}

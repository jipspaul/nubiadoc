import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/account_repository.dart';

class GetAvatarUseCase {
  final AccountRepository _repository;
  const GetAvatarUseCase(this._repository);

  Future<Either<Failure, AvatarImage?>> call() => _repository.getAvatar();
}

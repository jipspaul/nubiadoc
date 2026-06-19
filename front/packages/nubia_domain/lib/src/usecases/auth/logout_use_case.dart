import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/auth_repository.dart';

class LogoutUseCase {
  final AuthRepository _repository;
  const LogoutUseCase(this._repository);

  /// Clears stored tokens. Navigation to login is handled by the presentation
  /// layer (AuthBloc) in response to the returned [Right(null)].
  Future<Either<Failure, void>> call() => _repository.logout();
}

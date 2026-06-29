import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/auth_repository.dart';

class ProRegisterRequest extends Equatable {
  final String email;
  final String password;
  final String inviteToken;

  const ProRegisterRequest({
    required this.email,
    required this.password,
    required this.inviteToken,
  });

  @override
  List<Object?> get props => [email, password, inviteToken];
}

class ProRegisterUseCase {
  final AuthRepository _repository;
  const ProRegisterUseCase(this._repository);

  Future<Either<Failure, String>> call(ProRegisterRequest request) async {
    if (request.inviteToken.isEmpty) {
      return const Left(ValidationFailure(message: "Jeton d'invitation manquant."));
    }
    final result = await _repository.register(
      email: request.email,
      password: request.password,
      inviteToken: request.inviteToken,
    );
    return result.map((account) => account.id);
  }
}

import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/auth_repository.dart';

class ProRegisterRequest extends Equatable {
  final String email;
  final String password;
  final String firstName;
  final String lastName;
  final String? rpps;
  final String? adeli;
  final String raisonSociale;
  final String? siret;
  final String specialite;

  const ProRegisterRequest({
    required this.email,
    required this.password,
    required this.firstName,
    required this.lastName,
    this.rpps,
    this.adeli,
    required this.raisonSociale,
    this.siret,
    required this.specialite,
  });

  @override
  List<Object?> get props => [
        email,
        password,
        firstName,
        lastName,
        rpps,
        adeli,
        raisonSociale,
        siret,
        specialite,
      ];
}

class ProRegisterUseCase {
  final AuthRepository _repository;
  const ProRegisterUseCase(this._repository);

  Future<Either<Failure, String>> call(ProRegisterRequest request) async {
    if (request.rpps == null && request.adeli == null) {
      return const Left(
        ValidationFailure(message: 'RPPS ou ADELI requis.'),
      );
    }
    return _repository.registerPro(
      email: request.email,
      password: request.password,
      firstName: request.firstName,
      lastName: request.lastName,
      rpps: request.rpps,
      adeli: request.adeli,
      raisonSociale: request.raisonSociale,
      siret: request.siret,
      specialite: request.specialite,
    );
  }
}

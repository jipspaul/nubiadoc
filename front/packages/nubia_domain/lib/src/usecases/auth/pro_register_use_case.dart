import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/entities/pro_session.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/pro_register_repository.dart';

class ProRegisterUseCase {
  final ProRegisterRepository _repository;
  const ProRegisterUseCase(this._repository);

  Future<Either<Failure, ProSession>> call(ProRegisterRequest request) {
    if (request.email.isEmpty || !request.email.contains('@')) {
      return Future.value(
        const Left(ValidationFailure(message: 'Adresse e-mail invalide.')),
      );
    }
    if (request.password.length < 8) {
      return Future.value(
        const Left(
          ValidationFailure(
              message: 'Mot de passe trop court (min. 8 caractères).'),
        ),
      );
    }
    if (request.cabinet.raisonSociale.isEmpty) {
      return Future.value(
        const Left(
          ValidationFailure(message: 'La raison sociale est obligatoire.'),
        ),
      );
    }
    if (request.cabinet.specialite.isEmpty) {
      return Future.value(
        const Left(
          ValidationFailure(message: 'La spécialité est obligatoire.'),
        ),
      );
    }
    return _repository.register(request);
  }
}

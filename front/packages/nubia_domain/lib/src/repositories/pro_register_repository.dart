import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/entities/pro_session.dart';
import 'package:nubia_domain/src/error/failure.dart';

/// Infos du cabinet à créer.
class ProRegisterCabinetInfo {
  final String raisonSociale;
  final String? siret;
  final String specialite;

  const ProRegisterCabinetInfo({
    required this.raisonSociale,
    this.siret,
    required this.specialite,
  });
}

/// Infos du praticien à créer.
class ProRegisterPractitionerInfo {
  final String firstName;
  final String lastName;
  final String? rpps;
  final String? adeli;

  const ProRegisterPractitionerInfo({
    required this.firstName,
    required this.lastName,
    this.rpps,
    this.adeli,
  });
}

/// Commande miroir du body de POST /v1/pro/register.
class ProRegisterRequest {
  final String email;
  final String password;
  final ProRegisterCabinetInfo cabinet;
  final ProRegisterPractitionerInfo practitioner;

  const ProRegisterRequest({
    required this.email,
    required this.password,
    required this.cabinet,
    required this.practitioner,
  });
}

/// PORT — inscription praticien.
abstract class ProRegisterRepository {
  Future<Either<Failure, ProSession>> register(ProRegisterRequest request);
}

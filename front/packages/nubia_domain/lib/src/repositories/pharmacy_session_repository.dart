import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/entities/pharmacy_session.dart';
import 'package:nubia_domain/src/error/failure.dart';

/// PORT — session pharmacie (login commun → contexte `kind:"pharma"`).
abstract class PharmacySessionRepository {
  /// Appartenances pharmacie de l'utilisateur connecté (`GET /v1/me`).
  Future<Either<Failure, List<PharmacyMembership>>> myMemberships();

  /// Échange le token de login contre un JWT scopé pharmacie
  /// (`POST /v1/auth/select-pharmacy-context`). L'implémentation persiste le
  /// nouveau token d'accès (le refresh token du login commun est conservé).
  Future<Either<Failure, PharmacyContext>> selectContext(String pharmacyId);
}

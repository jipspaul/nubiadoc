import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/entities/pharmacy_session.dart';
import 'package:nubia_domain/src/error/failure.dart';

/// PORT — session pharmacie (login commun → contexte `kind:"pharma"`).
abstract class PharmacySessionRepository {
  /// Nom affichable de l'utilisateur connecté (#6170) + appartenances
  /// pharmacie (`GET /v1/me`).
  Future<
          Either<Failure,
              ({String? displayName, List<PharmacyMembership> memberships})>>
      myMemberships();

  /// Échange le token de login contre un JWT scopé pharmacie
  /// (`POST /v1/auth/select-pharmacy-context`). L'implémentation persiste le
  /// nouveau token d'accès (le refresh token du login commun est conservé).
  Future<Either<Failure, PharmacyContext>> selectContext(String pharmacyId);

  /// Hydrate le contexte sélectionné sans appel réseau — à utiliser quand un
  /// token déjà scopé `kind:"pharma"` est retrouvé en storage (app rouverte
  /// avec une session encore valide, cf. #7542) sans repasser par
  /// [selectContext]. Sans cet appel, le re-scope post-refresh (implémentation
  /// interne, branché sur `AuthInterceptor.onTokensRefreshed`) reste un no-op
  /// silencieux et toute l'app tombe en 403 après le refresh suivant.
  void hydrateSelectedPharmacyId(String pharmacyId);
}

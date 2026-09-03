import 'package:equatable/equatable.dart';
import 'package:nubia_domain/src/entities/pharmacy_order.dart';

/// Base class for all domain failures (left side of Either).
/// Never contains raw exceptions — only typed, user-facing info.
abstract class Failure extends Equatable {
  final String message;
  const Failure(this.message);

  @override
  List<Object?> get props => [message];
}

class NetworkFailure extends Failure {
  const NetworkFailure(
      [super.message = 'Erreur réseau. Vérifiez votre connexion.']);
}

/// Alerte clinique bloquante (#4057/#4058) : l'API a refusé (409
/// `clinical_risk_warning`) l'ajout d'un acte à risque au vu du dossier
/// médical du patient. Distinct de `ServerFailure` pour que l'UI affiche un
/// dialogue bloquant dédié plutôt qu'un simple snackbar d'erreur.
class ClinicalRiskWarningFailure extends Failure {
  const ClinicalRiskWarningFailure(super.message);
}

/// #6349 : `POST /pharmacy/orders/pickup-scan` a refusé (409
/// `pickup_order_mismatch`) car le token scanné appartient à une AUTRE
/// commande que celle transmise (`expected_order_id`) — le serveur n'a fait
/// AUCUNE transition. Distinct de `ServerFailure` pour que l'UI affiche
/// directement l'encart de non-correspondance avec [scannedOrder], sans
/// re-fetch.
class PickupOrderMismatchFailure extends Failure {
  const PickupOrderMismatchFailure(this.scannedOrder)
      : super('Ce code correspond à une autre commande.');

  final PharmacyOrder scannedOrder;

  @override
  List<Object?> get props => [message, scannedOrder];
}

class ServerFailure extends Failure {
  final int? statusCode;
  final String? code; // machine-stable error code from RFC 9457
  const ServerFailure({required String message, this.statusCode, this.code})
      : super(message);

  @override
  List<Object?> get props => [message, statusCode, code];
}

class UnauthorizedFailure extends Failure {
  const UnauthorizedFailure()
      : super('Session expirée. Veuillez vous reconnecter.');
}

class InvalidCredentialsFailure extends Failure {
  const InvalidCredentialsFailure() : super('E-mail ou mot de passe incorrect');
}

class InvalidInviteFailure extends Failure {
  const InvalidInviteFailure() : super('Invitation invalide ou expirée.');
}

class NotFoundFailure extends Failure {
  const NotFoundFailure([super.message = 'Ressource introuvable.']);
}

class ValidationFailure extends Failure {
  final Map<String, String> fieldErrors;
  const ValidationFailure(
      {required String message, this.fieldErrors = const {}})
      : super(message);

  @override
  List<Object?> get props => [message, fieldErrors];
}

class CacheFailure extends Failure {
  const CacheFailure([super.message = 'Erreur de stockage local.']);
}

class OfflineFailure extends Failure {
  const OfflineFailure() : super('Pas de connexion Internet.');
}

class ClinicalAccessDenied extends Failure {
  const ClinicalAccessDenied()
      : super('Accès clinique non autorisé pour ce rôle.');
}

class ParseFailure extends Failure {
  const ParseFailure([super.message = 'Erreur de décodage de la réponse.']);
}

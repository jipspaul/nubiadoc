import 'package:equatable/equatable.dart';

/// Base class for all domain failures (left side of Either).
/// Never contains raw exceptions — only typed, user-facing info.
abstract class Failure extends Equatable {
  final String message;
  const Failure(this.message);

  @override
  List<Object?> get props => [message];
}

class NetworkFailure extends Failure {
  const NetworkFailure([super.message = 'Erreur réseau. Vérifiez votre connexion.']);
}

class ServerFailure extends Failure {
  final int? statusCode;
  final String? code; // machine-stable error code from RFC 9457
  const ServerFailure({required String message, this.statusCode, this.code}) : super(message);

  @override
  List<Object?> get props => [message, statusCode, code];
}

class UnauthorizedFailure extends Failure {
  const UnauthorizedFailure() : super('Session expirée. Veuillez vous reconnecter.');
}

class NotFoundFailure extends Failure {
  const NotFoundFailure([super.message = 'Ressource introuvable.']);
}

class ValidationFailure extends Failure {
  final Map<String, String> fieldErrors;
  const ValidationFailure({required String message, this.fieldErrors = const {}}) : super(message);

  @override
  List<Object?> get props => [message, fieldErrors];
}

class CacheFailure extends Failure {
  const CacheFailure([super.message = 'Erreur de stockage local.']);
}

class OfflineFailure extends Failure {
  const OfflineFailure() : super('Pas de connexion Internet.');
}

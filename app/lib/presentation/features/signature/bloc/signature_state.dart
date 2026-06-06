import 'package:equatable/equatable.dart';

sealed class SignatureState extends Equatable {
  const SignatureState();

  @override
  List<Object?> get props => [];
}

/// État initial : en attente de démarrage.
final class SignaturePending extends SignatureState {
  const SignaturePending();
}

/// Ouverture du flux Yousign en cours (URL lancée, retour attendu).
final class SignatureInProgress extends SignatureState {
  const SignatureInProgress();
}

/// Signature complétée avec succès (eIDAS).
final class SignatureSigned extends SignatureState {
  const SignatureSigned();
}

/// Échec : message d'erreur user-facing.
final class SignatureFailed extends SignatureState {
  final String message;

  const SignatureFailed(this.message);

  @override
  List<Object?> get props => [message];
}

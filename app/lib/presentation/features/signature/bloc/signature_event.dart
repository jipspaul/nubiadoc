import 'package:equatable/equatable.dart';

sealed class SignatureEvent extends Equatable {
  const SignatureEvent();

  @override
  List<Object?> get props => [];
}

/// Lance le flux de signature Yousign pour [documentId].
/// [idempotencyKey] garantit que la demande n'est déclenchée qu'une seule fois.
final class SignatureStartRequested extends SignatureEvent {
  final String documentId;
  final String idempotencyKey;

  const SignatureStartRequested({
    required this.documentId,
    required this.idempotencyKey,
  });

  @override
  List<Object?> get props => [documentId, idempotencyKey];
}

/// Confirmé par le deep-link retour Yousign (statut signé).
final class SignatureConfirmed extends SignatureEvent {
  const SignatureConfirmed();
}

/// Annulation ou fermeture du navigateur externe.
final class SignatureCancelled extends SignatureEvent {
  const SignatureCancelled();
}

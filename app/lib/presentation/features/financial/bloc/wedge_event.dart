import 'package:equatable/equatable.dart';

sealed class WedgeEvent extends Equatable {
  const WedgeEvent();

  @override
  List<Object?> get props => [];
}

/// Charge le devis identifié par [quoteId].
final class WedgeQuoteLoadRequested extends WedgeEvent {
  const WedgeQuoteLoadRequested({required this.quoteId});

  final String quoteId;

  @override
  List<Object?> get props => [quoteId];
}

/// Lance le flux de signature Yousign pour le devis courant.
/// [idempotencyKey] est généré et fixé par l'écran avant le 1er tap.
final class WedgeSignatureRequested extends WedgeEvent {
  const WedgeSignatureRequested({required this.idempotencyKey});

  final String idempotencyKey;

  @override
  List<Object?> get props => [idempotencyKey];
}

/// Retour du deep-link nubia://signature/callback : confirme la signature.
final class WedgeSignatureCallbackReceived extends WedgeEvent {
  const WedgeSignatureCallbackReceived();
}

/// Lance le paiement de l'acompte.
/// [idempotencyKey] est généré et fixé par l'écran avant le 1er tap.
final class WedgeDepositRequested extends WedgeEvent {
  const WedgeDepositRequested({required this.idempotencyKey});

  final String idempotencyKey;

  @override
  List<Object?> get props => [idempotencyKey];
}

/// Réessaie le paiement en conservant l'idempotency-key existante.
final class WedgeDepositRetryRequested extends WedgeEvent {
  const WedgeDepositRetryRequested();
}

/// Demande un nouveau devis (devis expiré).
final class WedgeNewQuoteRequested extends WedgeEvent {
  const WedgeNewQuoteRequested();
}

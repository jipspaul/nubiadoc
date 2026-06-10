import 'package:equatable/equatable.dart';
import 'package:nubia_patient/domain/entities/quote.dart';

sealed class WedgeState extends Equatable {
  const WedgeState();

  @override
  List<Object?> get props => [];
}

/// En cours de chargement du devis.
final class WedgeLoading extends WedgeState {
  const WedgeLoading();
}

/// Devis chargé — affiche le détail + CTA « Signer le devis ».
final class WedgeQuoteLoaded extends WedgeState {
  const WedgeQuoteLoaded(this.quote);

  final Quote quote;

  @override
  List<Object?> get props => [quote];
}

/// Redirection Yousign en cours (URL ouverte, attente du callback).
final class WedgeSignatureInProgress extends WedgeState {
  const WedgeSignatureInProgress({
    required this.quote,
    required this.signatureUrl,
  });

  final Quote quote;
  final String signatureUrl;

  @override
  List<Object?> get props => [quote, signatureUrl];
}

/// Signature confirmée — prêt à payer (ou skip si acompte = 0).
final class WedgeSignatureDone extends WedgeState {
  const WedgeSignatureDone(this.quote);

  final Quote quote;

  @override
  List<Object?> get props => [quote];
}

/// Paiement en cours.
final class WedgePaymentInProgress extends WedgeState {
  const WedgePaymentInProgress({
    required this.quote,
    required this.idempotencyKey,
  });

  final Quote quote;
  final String idempotencyKey;

  @override
  List<Object?> get props => [quote, idempotencyKey];
}

/// Paiement réussi.
final class WedgePaymentSuccess extends WedgeState {
  const WedgePaymentSuccess(this.quote);

  final Quote quote;

  @override
  List<Object?> get props => [quote];
}

/// Erreur générique avec message user-facing.
final class WedgeError extends WedgeState {
  const WedgeError({required this.message, this.quote});

  final String message;

  /// Conservé pour permettre le retry sans rechargement.
  final Quote? quote;

  @override
  List<Object?> get props => [message, quote];
}

/// Devis expiré — demander un nouveau devis.
final class WedgeQuoteExpired extends WedgeState {
  const WedgeQuoteExpired(this.quote);

  final Quote quote;

  @override
  List<Object?> get props => [quote];
}

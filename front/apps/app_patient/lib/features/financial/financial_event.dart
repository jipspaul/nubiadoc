import 'package:equatable/equatable.dart';

sealed class FinancialEvent extends Equatable {
  const FinancialEvent();

  @override
  List<Object?> get props => [];
}

/// Charge la liste des devis en attente.
final class FinancialLoadRequested extends FinancialEvent {
  const FinancialLoadRequested();
}

/// Sélectionne un devis par son identifiant (charge le détail).
final class FinancialQuoteSelected extends FinancialEvent {
  const FinancialQuoteSelected(this.quoteId);

  final String quoteId;

  @override
  List<Object?> get props => [quoteId];
}

/// Retour arrière vers la liste depuis le détail.
final class FinancialBackToList extends FinancialEvent {
  const FinancialBackToList();
}

/// Signe le devis sélectionné (synchrone — stub Yousign, pas de redirection).
final class FinancialSignatureRequested extends FinancialEvent {
  const FinancialSignatureRequested();
}

/// Lance le paiement de l'acompte.
/// [idempotencyKey] doit être fixé par l'écran avant le premier appel.
final class FinancialPaymentRequested extends FinancialEvent {
  const FinancialPaymentRequested({required this.idempotencyKey});

  final String idempotencyKey;

  @override
  List<Object?> get props => [idempotencyKey];
}

/// Demande le téléchargement du devis signé (PDF horodaté du coffre) pour
/// le devis actuellement affiché en détail.
final class FinancialDownloadRequested extends FinancialEvent {
  const FinancialDownloadRequested();
}

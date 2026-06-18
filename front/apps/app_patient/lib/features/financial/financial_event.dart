import 'package:equatable/equatable.dart';

sealed class FinancialEvent extends Equatable {
  const FinancialEvent();

  @override
  List<Object?> get props => [];
}

/// Charge la liste des devis en attente d'action.
final class FinancialLoadRequested extends FinancialEvent {
  const FinancialLoadRequested();
}

/// Sélectionne un devis pour afficher son détail.
final class FinancialQuoteSelected extends FinancialEvent {
  const FinancialQuoteSelected(this.quoteId);

  final String quoteId;

  @override
  List<Object?> get props => [quoteId];
}

/// Retourne à la liste des devis.
final class FinancialBackToList extends FinancialEvent {
  const FinancialBackToList();
}

/// Lance le flux de signature Yousign pour le devis courant.
final class FinancialSignatureRequested extends FinancialEvent {
  const FinancialSignatureRequested();
}

/// Confirme que la signature Yousign est terminée (retour deep-link).
final class FinancialSignatureCompleted extends FinancialEvent {
  const FinancialSignatureCompleted();
}

/// Lance le paiement de l'acompte.
final class FinancialPaymentRequested extends FinancialEvent {
  const FinancialPaymentRequested({required this.idempotencyKey});

  final String idempotencyKey;

  @override
  List<Object?> get props => [idempotencyKey];
}

import 'package:equatable/equatable.dart';
import 'package:nubia_domain/nubia_domain.dart';

sealed class FinancialState extends Equatable {
  const FinancialState();

  @override
  List<Object?> get props => [];
}

final class FinancialInitial extends FinancialState {
  const FinancialInitial();
}

final class FinancialLoading extends FinancialState {
  const FinancialLoading();
}

/// Liste des devis chargée.
final class FinancialLoaded extends FinancialState {
  const FinancialLoaded(this.quotes);

  final List<Quote> quotes;

  @override
  List<Object?> get props => [quotes];
}

/// Détail d'un devis affiché. [quotes] est conservé pour revenir à la liste.
final class FinancialQuoteDetail extends FinancialState {
  const FinancialQuoteDetail({required this.quote, required this.quotes});

  final Quote quote;
  final List<Quote> quotes;

  @override
  List<Object?> get props => [quote, quotes];
}

/// Signature Yousign en cours (URL ouverte, attente du callback).
final class FinancialSignatureInProgress extends FinancialState {
  const FinancialSignatureInProgress({
    required this.quote,
    required this.quotes,
    required this.signatureUrl,
  });

  final Quote quote;
  final List<Quote> quotes;
  final String signatureUrl;

  @override
  List<Object?> get props => [quote, quotes, signatureUrl];
}

/// Paiement de l'acompte en cours.
final class FinancialPaymentInProgress extends FinancialState {
  const FinancialPaymentInProgress({
    required this.quote,
    required this.quotes,
  });

  final Quote quote;
  final List<Quote> quotes;

  @override
  List<Object?> get props => [quote, quotes];
}

/// Paiement réussi.
final class FinancialPaymentSuccess extends FinancialState {
  const FinancialPaymentSuccess({required this.quote, required this.quotes});

  final Quote quote;
  final List<Quote> quotes;

  @override
  List<Object?> get props => [quote, quotes];
}

/// Erreur avec message utilisateur.
final class FinancialError extends FinancialState {
  const FinancialError({required this.message, this.quotes = const []});

  final String message;

  /// Conservé pour permettre un retour à la liste sans rechargement.
  final List<Quote> quotes;

  @override
  List<Object?> get props => [message, quotes];
}

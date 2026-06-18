import 'package:equatable/equatable.dart';
import 'package:nubia_domain/nubia_domain.dart';

sealed class FinancialState extends Equatable {
  const FinancialState();

  @override
  List<Object?> get props => [];
}

/// État initial avant tout chargement.
final class FinancialInitial extends FinancialState {
  const FinancialInitial();
}

/// Chargement en cours (liste ou détail).
final class FinancialLoading extends FinancialState {
  const FinancialLoading();
}

/// Liste de devis chargée avec succès.
final class FinancialLoaded extends FinancialState {
  const FinancialLoaded(this.quotes);

  final List<Quote> quotes;

  @override
  List<Object?> get props => [quotes];
}

/// Détail d'un devis affiché — affiche CTA « Signer » ou « Payer ».
final class FinancialQuoteDetail extends FinancialState {
  const FinancialQuoteDetail({required this.quote, required this.quotes});

  final Quote quote;
  final List<Quote> quotes;

  @override
  List<Object?> get props => [quote, quotes];
}

/// URL Yousign obtenue, attente de la confirmation de signature.
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

/// Paiement en cours.
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
  const FinancialPaymentSuccess({
    required this.quote,
    required this.quotes,
  });

  final Quote quote;
  final List<Quote> quotes;

  @override
  List<Object?> get props => [quote, quotes];
}

/// Erreur avec message user-facing.
final class FinancialError extends FinancialState {
  const FinancialError({required this.message, this.quotes = const []});

  final String message;
  final List<Quote> quotes;

  @override
  List<Object?> get props => [message, quotes];
}

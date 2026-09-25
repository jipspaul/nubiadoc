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
  const FinancialQuoteDetail({
    required this.quote,
    required this.quotes,
    this.documentUrl,
    this.attachments = const [],
    this.attestation,
    this.paymentSchedule,
  });

  final Quote quote;
  final List<Quote> quotes;

  /// URL signée résolue par un téléchargement du devis signé en cours
  /// (déclenche l'ouverture externe, cf. `implant_passport_cubit.dart`).
  final String? documentUrl;

  /// Pièces jointes du devis (consentements, ordonnances, courriers, #7201).
  final List<QuoteAttachment> attachments;

  /// Attestation d'information à lire et signer avant de pouvoir signer le
  /// devis (#7201/#7203) — `null` si aucune n'a été déposée par le cabinet.
  final QuoteAttestation? attestation;

  /// Échéancier `active` posé par le praticien sur ce devis (#7018, #4072) —
  /// `null` si aucun n'a été posé. Tant qu'il existe, l'API refuse tout
  /// paiement ad hoc sur le devis (garde #5669) : le patient doit régler via
  /// ces jalons, jamais via l'acompte générique.
  final PaymentSchedule? paymentSchedule;

  @override
  List<Object?> get props =>
      [quote, quotes, documentUrl, attachments, attestation, paymentSchedule];
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

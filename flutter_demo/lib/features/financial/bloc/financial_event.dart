import 'package:equatable/equatable.dart';

sealed class FinancialEvent extends Equatable {
  const FinancialEvent();

  @override
  List<Object?> get props => [];
}

/// Déclenche le chargement du résumé financier.
final class FinancialLoadRequested extends FinancialEvent {
  const FinancialLoadRequested({required this.patientId});

  final String patientId;

  @override
  List<Object?> get props => [patientId];
}

/// Déclenche un paiement Stripe in-app pour le jalon [milestoneId].
final class FinancialPaymentRequested extends FinancialEvent {
  const FinancialPaymentRequested({
    required this.patientId,
    required this.milestoneId,
    required this.amountCents,
  });

  final String patientId;
  final String milestoneId;
  final int amountCents;

  @override
  List<Object?> get props => [patientId, milestoneId, amountCents];
}

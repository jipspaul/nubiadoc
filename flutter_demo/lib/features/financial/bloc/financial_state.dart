import 'package:equatable/equatable.dart';

import '../models/financial_summary.dart';

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

final class FinancialLoaded extends FinancialState {
  const FinancialLoaded(this.summary);

  final FinancialSummary summary;

  @override
  List<Object?> get props => [summary];
}

final class FinancialError extends FinancialState {
  const FinancialError(this.message);

  final String message;

  @override
  List<Object?> get props => [message];
}

/// Émis pendant qu'un paiement Stripe est en cours.
final class FinancialPaymentInProgress extends FinancialState {
  const FinancialPaymentInProgress(this.summary);

  final FinancialSummary summary;

  @override
  List<Object?> get props => [summary];
}

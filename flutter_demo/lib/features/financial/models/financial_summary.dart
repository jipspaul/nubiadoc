import 'package:equatable/equatable.dart';

/// Statut d'un devis/facture.
enum DocumentStatus { draft, pending, paid, overdue }

/// Statut d'un jalon de règlement.
enum MilestoneStatus { upcoming, paid, overdue }

/// Un devis ou une facture.
class FinancialDocument extends Equatable {
  const FinancialDocument({
    required this.id,
    required this.label,
    required this.amountCents,
    required this.status,
    required this.date,
  });

  final String id;
  final String label;
  final int amountCents;
  final DocumentStatus status;
  final DateTime date;

  @override
  List<Object?> get props => [id, label, amountCents, status, date];
}

/// Un jalon dans l'échéancier de paiement.
class PaymentMilestone extends Equatable {
  const PaymentMilestone({
    required this.id,
    required this.label,
    required this.amountCents,
    required this.dueDate,
    required this.status,
  });

  final String id;
  final String label;
  final int amountCents;
  final DateTime dueDate;
  final MilestoneStatus status;

  @override
  List<Object?> get props => [id, label, amountCents, dueDate, status];
}

/// Résumé financier complet d'un patient.
class FinancialSummary extends Equatable {
  const FinancialSummary({
    required this.totalDueCents,
    required this.totalPaidCents,
    required this.quotes,
    required this.invoices,
    required this.milestones,
  });

  final int totalDueCents;
  final int totalPaidCents;
  final List<FinancialDocument> quotes;
  final List<FinancialDocument> invoices;
  final List<PaymentMilestone> milestones;

  int get remainingCents => totalDueCents - totalPaidCents;

  double get paidFraction =>
      totalDueCents == 0 ? 0.0 : (totalPaidCents / totalDueCents).clamp(0.0, 1.0);

  @override
  List<Object?> get props =>
      [totalDueCents, totalPaidCents, quotes, invoices, milestones];
}

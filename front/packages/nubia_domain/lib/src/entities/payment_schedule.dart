import 'package:equatable/equatable.dart';

/// Statut d'un jalon (`payment_schedule.installments[].status`, cf.
/// `api/src/payment_schedules.rs`).
enum InstallmentStatus {
  pending,
  paid,
  unknown;

  static InstallmentStatus fromApi(String raw) => switch (raw) {
        'pending' => InstallmentStatus.pending,
        'paid' => InstallmentStatus.paid,
        _ => InstallmentStatus.unknown,
      };
}

/// Un jalon daté d'un échéancier de paiement.
class PaymentScheduleInstallment extends Equatable {
  final DateTime date;
  final int amountCents;
  final InstallmentStatus status;

  const PaymentScheduleInstallment({
    required this.date,
    required this.amountCents,
    required this.status,
  });

  @override
  List<Object?> get props => [date, amountCents, status];
}

/// Statut d'un échéancier (`payment_schedule.status`).
enum PaymentScheduleStatus {
  active,
  completed,
  cancelled,
  unknown;

  static PaymentScheduleStatus fromApi(String raw) => switch (raw) {
        'active' => PaymentScheduleStatus.active,
        'completed' => PaymentScheduleStatus.completed,
        'cancelled' => PaymentScheduleStatus.cancelled,
        _ => PaymentScheduleStatus.unknown,
      };
}

/// Échéancier de paiement multi-jalons posé par le praticien sur un devis
/// signé (#4072). Source : `GET /v1/payment-schedules` (côté patient).
///
/// Tant qu'un échéancier `active` existe sur un devis, l'API refuse tout
/// autre paiement ad hoc sur ce même devis (`422 validation_error`, garde
/// #5669 côté `create_payment_intent`/`create_payment_schedule`) : le patient
/// doit régler via les jalons de cet échéancier, jamais via l'acompte
/// générique.
class PaymentSchedule extends Equatable {
  final String id;
  final String? quoteId;
  final int totalAmountCents;
  final List<PaymentScheduleInstallment> installments;
  final PaymentScheduleStatus status;
  final DateTime createdAt;

  const PaymentSchedule({
    required this.id,
    this.quoteId,
    required this.totalAmountCents,
    required this.installments,
    required this.status,
    required this.createdAt,
  });

  bool get isActive => status == PaymentScheduleStatus.active;

  @override
  List<Object?> get props => [id, status];
}

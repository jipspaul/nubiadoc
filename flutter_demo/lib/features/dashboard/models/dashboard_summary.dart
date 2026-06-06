import 'package:equatable/equatable.dart';

/// Prochain rendez-vous résumé.
class NextAppointment extends Equatable {
  const NextAppointment({
    required this.id,
    required this.providerName,
    required this.startsAt,
    required this.motif,
  });

  final String id;
  final String providerName;
  final DateTime startsAt;
  final String motif;

  @override
  List<Object?> get props => [id, providerName, startsAt, motif];
}

/// Document à signer (devis en attente de signature).
class ToSignItem extends Equatable {
  const ToSignItem({required this.quoteId, required this.label});

  final String quoteId;
  final String label;

  @override
  List<Object?> get props => [quoteId, label];
}

/// Jalon de paiement en attente.
class ToPayItem extends Equatable {
  const ToPayItem({
    required this.milestoneId,
    required this.label,
    required this.amountCents,
  });

  final String milestoneId;
  final String label;
  final int amountCents;

  @override
  List<Object?> get props => [milestoneId, label, amountCents];
}

/// Rappel patient (ex. apporter carte Vitale).
class ReminderItem extends Equatable {
  const ReminderItem({required this.id, required this.label});

  final String id;
  final String label;

  @override
  List<Object?> get props => [id, label];
}

/// Questionnaire à compléter.
class QuestionnaireTodo extends Equatable {
  const QuestionnaireTodo({required this.id, required this.title});

  final String id;
  final String title;

  @override
  List<Object?> get props => [id, title];
}

/// Vue agrégée dashboard patient — contrat GET /v1/dashboard.
class DashboardSummary extends Equatable {
  const DashboardSummary({
    this.nextAppointment,
    required this.toSign,
    required this.toPay,
    required this.unreadMessages,
    required this.questionnairesTodo,
    required this.reminders,
  });

  final NextAppointment? nextAppointment;
  final List<ToSignItem> toSign;
  final List<ToPayItem> toPay;
  final int unreadMessages;
  final List<QuestionnaireTodo> questionnairesTodo;
  final List<ReminderItem> reminders;

  @override
  List<Object?> get props => [
        nextAppointment,
        toSign,
        toPay,
        unreadMessages,
        questionnairesTodo,
        reminders,
      ];
}

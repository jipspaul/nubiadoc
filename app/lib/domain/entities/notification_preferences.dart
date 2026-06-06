import 'package:equatable/equatable.dart';

/// User preferences for push/in-app notification categories.
///
/// Each flag corresponds to one notification type that can be toggled
/// on [PATCH /v1/account/notification-preferences].
class NotificationPreferences extends Equatable {
  final bool appointments;
  final bool documents;
  final bool messages;
  final bool payments;
  final bool prevention;

  const NotificationPreferences({
    required this.appointments,
    required this.documents,
    required this.messages,
    required this.payments,
    required this.prevention,
  });

  /// All channels enabled — sensible default before the first fetch.
  const NotificationPreferences.allEnabled()
      : appointments = true,
        documents = true,
        messages = true,
        payments = true,
        prevention = true;

  NotificationPreferences copyWith({
    bool? appointments,
    bool? documents,
    bool? messages,
    bool? payments,
    bool? prevention,
  }) {
    return NotificationPreferences(
      appointments: appointments ?? this.appointments,
      documents: documents ?? this.documents,
      messages: messages ?? this.messages,
      payments: payments ?? this.payments,
      prevention: prevention ?? this.prevention,
    );
  }

  @override
  List<Object?> get props =>
      [appointments, documents, messages, payments, prevention];
}

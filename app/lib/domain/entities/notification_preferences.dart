import 'package:equatable/equatable.dart';

/// User preferences for notification channels and event types.
///
/// Channel flags (push/email/SMS) and per-type flags can each be toggled
/// independently via [PATCH /v1/account/notification-preferences].
class NotificationPreferences extends Equatable {
  // --- Channels ---
  final bool pushEnabled;
  final bool emailEnabled;
  final bool smsEnabled;

  // --- Event types ---
  final bool appointments;
  final bool documents;
  final bool messages;
  final bool payments;
  final bool prevention;

  const NotificationPreferences({
    required this.pushEnabled,
    required this.emailEnabled,
    required this.smsEnabled,
    required this.appointments,
    required this.documents,
    required this.messages,
    required this.payments,
    required this.prevention,
  });

  /// All channels and types enabled — sensible default before the first fetch.
  const NotificationPreferences.allEnabled()
      : pushEnabled = true,
        emailEnabled = true,
        smsEnabled = true,
        appointments = true,
        documents = true,
        messages = true,
        payments = true,
        prevention = true;

  NotificationPreferences copyWith({
    bool? pushEnabled,
    bool? emailEnabled,
    bool? smsEnabled,
    bool? appointments,
    bool? documents,
    bool? messages,
    bool? payments,
    bool? prevention,
  }) {
    return NotificationPreferences(
      pushEnabled: pushEnabled ?? this.pushEnabled,
      emailEnabled: emailEnabled ?? this.emailEnabled,
      smsEnabled: smsEnabled ?? this.smsEnabled,
      appointments: appointments ?? this.appointments,
      documents: documents ?? this.documents,
      messages: messages ?? this.messages,
      payments: payments ?? this.payments,
      prevention: prevention ?? this.prevention,
    );
  }

  @override
  List<Object?> get props => [
        pushEnabled,
        emailEnabled,
        smsEnabled,
        appointments,
        documents,
        messages,
        payments,
        prevention,
      ];
}

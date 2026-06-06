import 'package:nubia_patient/domain/entities/notification_preferences.dart';

class NotificationPreferencesDto {
  // Channels
  final bool pushEnabled;
  final bool emailEnabled;
  final bool smsEnabled;

  // Event types
  final bool appointments;
  final bool documents;
  final bool messages;
  final bool payments;
  final bool prevention;

  const NotificationPreferencesDto({
    required this.pushEnabled,
    required this.emailEnabled,
    required this.smsEnabled,
    required this.appointments,
    required this.documents,
    required this.messages,
    required this.payments,
    required this.prevention,
  });

  factory NotificationPreferencesDto.fromJson(Map<String, dynamic> json) =>
      NotificationPreferencesDto(
        pushEnabled: json['push_enabled'] as bool? ?? true,
        emailEnabled: json['email_enabled'] as bool? ?? true,
        smsEnabled: json['sms_enabled'] as bool? ?? true,
        appointments: json['appointments'] as bool? ?? true,
        documents: json['documents'] as bool? ?? true,
        messages: json['messages'] as bool? ?? true,
        payments: json['payments'] as bool? ?? true,
        prevention: json['prevention'] as bool? ?? true,
      );

  Map<String, dynamic> toJson() => {
        'push_enabled': pushEnabled,
        'email_enabled': emailEnabled,
        'sms_enabled': smsEnabled,
        'appointments': appointments,
        'documents': documents,
        'messages': messages,
        'payments': payments,
        'prevention': prevention,
      };

  NotificationPreferences toDomain() => NotificationPreferences(
        pushEnabled: pushEnabled,
        emailEnabled: emailEnabled,
        smsEnabled: smsEnabled,
        appointments: appointments,
        documents: documents,
        messages: messages,
        payments: payments,
        prevention: prevention,
      );

  factory NotificationPreferencesDto.fromDomain(
    NotificationPreferences prefs,
  ) =>
      NotificationPreferencesDto(
        pushEnabled: prefs.pushEnabled,
        emailEnabled: prefs.emailEnabled,
        smsEnabled: prefs.smsEnabled,
        appointments: prefs.appointments,
        documents: prefs.documents,
        messages: prefs.messages,
        payments: prefs.payments,
        prevention: prefs.prevention,
      );
}

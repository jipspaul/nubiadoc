import 'package:nubia_patient/domain/entities/notification_preferences.dart';

class NotificationPreferencesDto {
  final bool appointments;
  final bool documents;
  final bool messages;
  final bool payments;
  final bool prevention;

  const NotificationPreferencesDto({
    required this.appointments,
    required this.documents,
    required this.messages,
    required this.payments,
    required this.prevention,
  });

  factory NotificationPreferencesDto.fromJson(Map<String, dynamic> json) =>
      NotificationPreferencesDto(
        appointments: json['appointments'] as bool? ?? true,
        documents: json['documents'] as bool? ?? true,
        messages: json['messages'] as bool? ?? true,
        payments: json['payments'] as bool? ?? true,
        prevention: json['prevention'] as bool? ?? true,
      );

  Map<String, dynamic> toJson() => {
        'appointments': appointments,
        'documents': documents,
        'messages': messages,
        'payments': payments,
        'prevention': prevention,
      };

  NotificationPreferences toDomain() => NotificationPreferences(
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
        appointments: prefs.appointments,
        documents: prefs.documents,
        messages: prefs.messages,
        payments: prefs.payments,
        prevention: prefs.prevention,
      );
}

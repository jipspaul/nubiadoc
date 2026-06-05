import 'package:nubia_patient/domain/repositories/dashboard_repository.dart';

class DashboardDto {
  final int upcomingAppointments;
  final int documentsToSign;
  final int pendingPaymentsCents;
  final int unreadMessages;
  final int pendingQuestionnaires;

  const DashboardDto({
    required this.upcomingAppointments,
    required this.documentsToSign,
    required this.pendingPaymentsCents,
    required this.unreadMessages,
    required this.pendingQuestionnaires,
  });

  factory DashboardDto.fromJson(Map<String, dynamic> json) => DashboardDto(
        upcomingAppointments: (json['upcoming_appointments'] as num).toInt(),
        documentsToSign: (json['documents_to_sign'] as num).toInt(),
        pendingPaymentsCents: (json['pending_payments_cents'] as num).toInt(),
        unreadMessages: (json['unread_messages'] as num).toInt(),
        pendingQuestionnaires: (json['pending_questionnaires'] as num).toInt(),
      );

  DashboardSummary toDomain() => DashboardSummary(
        upcomingAppointments: upcomingAppointments,
        documentsToSign: documentsToSign,
        pendingPaymentsCents: pendingPaymentsCents,
        unreadMessages: unreadMessages,
        pendingQuestionnaires: pendingQuestionnaires,
      );
}

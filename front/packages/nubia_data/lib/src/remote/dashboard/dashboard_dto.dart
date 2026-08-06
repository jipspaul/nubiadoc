import 'package:nubia_domain/src/repositories/dashboard_repository.dart';

class DashboardDto {
  final int upcomingAppointments;
  final int documentsToSign;
  final int pendingPaymentsCents;
  final int unreadMessages;

  const DashboardDto({
    required this.upcomingAppointments,
    required this.documentsToSign,
    required this.pendingPaymentsCents,
    required this.unreadMessages,
  });

  factory DashboardDto.fromJson(Map<String, dynamic> json) {
    final toSign = (json['to_sign'] as List<dynamic>?) ?? [];
    final toPay = (json['to_pay'] as List<dynamic>?) ?? [];
    final pendingPaymentsCents = toPay.fold<int>(
      0,
      (sum, item) => sum + (item['amount_cents'] as num).toInt(),
    );
    return DashboardDto(
      upcomingAppointments: json['next_appointment'] != null ? 1 : 0,
      documentsToSign: toSign.length,
      pendingPaymentsCents: pendingPaymentsCents,
      unreadMessages: (json['unread_messages'] as num).toInt(),
    );
  }

  DashboardSummary toDomain() => DashboardSummary(
        upcomingAppointments: upcomingAppointments,
        documentsToSign: documentsToSign,
        pendingPaymentsCents: pendingPaymentsCents,
        unreadMessages: unreadMessages,
      );
}

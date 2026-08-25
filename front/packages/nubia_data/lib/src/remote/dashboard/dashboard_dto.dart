import 'package:nubia_domain/src/repositories/dashboard_repository.dart';

class NextAppointmentDto {
  final String appointmentId;
  final DateTime startsAt;
  final String? practitionerName;
  final String? reason;
  final List<String>? addressLines;

  const NextAppointmentDto({
    required this.appointmentId,
    required this.startsAt,
    this.practitionerName,
    this.reason,
    this.addressLines,
  });

  factory NextAppointmentDto.fromJson(Map<String, dynamic> json) =>
      NextAppointmentDto(
        appointmentId: json['appointment_id'] as String,
        startsAt: DateTime.parse(json['starts_at'] as String),
        practitionerName: json['practitioner_name'] as String?,
        reason: json['reason'] as String?,
        addressLines: (json['address_lines'] as List<dynamic>?)
            ?.map((line) => line as String)
            .toList(),
      );

  NextAppointmentSummary toDomain() => NextAppointmentSummary(
        appointmentId: appointmentId,
        startsAt: startsAt,
        practitionerName: practitionerName,
        reason: reason,
        addressLines: addressLines,
      );
}

class DashboardDto {
  final int upcomingAppointments;
  final int documentsToSign;
  final int pendingPaymentsCents;
  final int unreadMessages;
  final NextAppointmentDto? nextAppointment;

  const DashboardDto({
    required this.upcomingAppointments,
    required this.documentsToSign,
    required this.pendingPaymentsCents,
    required this.unreadMessages,
    this.nextAppointment,
  });

  factory DashboardDto.fromJson(Map<String, dynamic> json) {
    final toSign = (json['to_sign'] as List<dynamic>?) ?? [];
    final toPay = (json['to_pay'] as List<dynamic>?) ?? [];
    final pendingPaymentsCents = toPay.fold<int>(
      0,
      (sum, item) => sum + (item['amount_cents'] as num).toInt(),
    );
    final nextAppointmentJson =
        json['next_appointment'] as Map<String, dynamic>?;
    final nextAppointment = nextAppointmentJson != null
        ? NextAppointmentDto.fromJson(nextAppointmentJson)
        : null;
    return DashboardDto(
      upcomingAppointments: nextAppointment != null ? 1 : 0,
      documentsToSign: toSign.length,
      pendingPaymentsCents: pendingPaymentsCents,
      unreadMessages: (json['unread_messages'] as num).toInt(),
      nextAppointment: nextAppointment,
    );
  }

  DashboardSummary toDomain() => DashboardSummary(
        upcomingAppointments: upcomingAppointments,
        documentsToSign: documentsToSign,
        pendingPaymentsCents: pendingPaymentsCents,
        unreadMessages: unreadMessages,
        nextAppointment: nextAppointment?.toDomain(),
      );
}

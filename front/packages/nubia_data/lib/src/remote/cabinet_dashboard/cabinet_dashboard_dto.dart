import 'package:nubia_domain/nubia_domain.dart';

class CabinetDashboardDto {
  final int todayAppointments;
  final int waitingRoomCount;
  final int unreadMessages;
  final int pendingConfirmations;
  final int weeklyCompletedActs;
  final int weeklyFeesCents;
  final int weeklyNoShowCount;

  /// Patient suivant en salle d'attente (#5045) — voir
  /// [ProDashboardSummary.nextPatientName] pour la provenance des champs.
  final String? nextPatientName;
  final String? nextPatientReason;
  final DateTime? nextPatientAppointmentTime;
  final int? nextPatientDurationMinutes;
  final int? nextPatientWaitingMinutes;
  final String? nextPatientAppointmentId;
  final String? nextPatientPatientId;
  final String? nextPatientAllergyLabel;
  final int? nextPatientTreatmentPlanCents;
  final DateTime? nextPatientLastVisitAt;

  const CabinetDashboardDto({
    required this.todayAppointments,
    required this.waitingRoomCount,
    required this.unreadMessages,
    required this.pendingConfirmations,
    required this.weeklyCompletedActs,
    required this.weeklyFeesCents,
    required this.weeklyNoShowCount,
    this.nextPatientName,
    this.nextPatientReason,
    this.nextPatientAppointmentTime,
    this.nextPatientDurationMinutes,
    this.nextPatientWaitingMinutes,
    this.nextPatientAppointmentId,
    this.nextPatientPatientId,
    this.nextPatientAllergyLabel,
    this.nextPatientTreatmentPlanCents,
    this.nextPatientLastVisitAt,
  });

  factory CabinetDashboardDto.fromJson(Map<String, dynamic> json) {
    final appointmentTime = json['next_patient_appointment_time'] as String?;
    final lastVisitAt = json['next_patient_last_visit_at'] as String?;
    return CabinetDashboardDto(
      todayAppointments: (json['today_appointments'] as num?)?.toInt() ?? 0,
      waitingRoomCount: (json['waiting_room_count'] as num?)?.toInt() ?? 0,
      unreadMessages: (json['unread_messages'] as num?)?.toInt() ?? 0,
      pendingConfirmations:
          (json['pending_confirmations'] as num?)?.toInt() ?? 0,
      weeklyCompletedActs:
          (json['weekly_completed_acts'] as num?)?.toInt() ?? 0,
      weeklyFeesCents: (json['weekly_fees_cents'] as num?)?.toInt() ?? 0,
      weeklyNoShowCount: (json['weekly_no_show_count'] as num?)?.toInt() ?? 0,
      nextPatientName: json['next_patient_name'] as String?,
      nextPatientReason: json['next_patient_reason'] as String?,
      nextPatientAppointmentTime:
          appointmentTime == null ? null : DateTime.tryParse(appointmentTime),
      nextPatientDurationMinutes:
          (json['next_patient_duration_minutes'] as num?)?.toInt(),
      nextPatientWaitingMinutes:
          (json['next_patient_waiting_minutes'] as num?)?.toInt(),
      nextPatientAppointmentId: json['next_patient_appointment_id'] as String?,
      nextPatientPatientId: json['next_patient_patient_id'] as String?,
      nextPatientAllergyLabel: json['next_patient_allergy_label'] as String?,
      nextPatientTreatmentPlanCents:
          (json['next_patient_treatment_plan_cents'] as num?)?.toInt(),
      nextPatientLastVisitAt:
          lastVisitAt == null ? null : DateTime.tryParse(lastVisitAt),
    );
  }

  ProDashboardSummary toDomain() => ProDashboardSummary(
        todayAppointments: todayAppointments,
        waitingRoomCount: waitingRoomCount,
        unreadMessages: unreadMessages,
        pendingConfirmations: pendingConfirmations,
        weeklyCompletedActs: weeklyCompletedActs,
        weeklyFeesCents: weeklyFeesCents,
        weeklyNoShowCount: weeklyNoShowCount,
        nextPatientName: nextPatientName,
        nextPatientReason: nextPatientReason,
        nextPatientAppointmentTime: nextPatientAppointmentTime,
        nextPatientDurationMinutes: nextPatientDurationMinutes,
        nextPatientWaitingMinutes: nextPatientWaitingMinutes,
        nextPatientAppointmentId: nextPatientAppointmentId,
        nextPatientPatientId: nextPatientPatientId,
        nextPatientAllergyLabel: nextPatientAllergyLabel,
        nextPatientTreatmentPlanCents: nextPatientTreatmentPlanCents,
        nextPatientLastVisitAt: nextPatientLastVisitAt,
      );
}

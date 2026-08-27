import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';

class ProDashboardSummary {
  final int todayAppointments;
  final int waitingRoomCount;
  final int unreadMessages;
  final int pendingConfirmations;

  /// Nombre d'actes réalisés cette semaine (lundi au vendredi, #5051).
  final int weeklyCompletedActs;

  /// Honoraires (encaissés + engagés) cette semaine, en centimes (#5051).
  final int weeklyFeesCents;

  /// Nombre de rendez-vous non honorés cette semaine (#5051).
  final int weeklyNoShowCount;

  /// Patient suivant en salle d'attente (#5045, hero du tableau de bord) —
  /// `null` quand personne n'attend, ce qui masque le hero. Nom, motif,
  /// heure et temps d'attente sont dérivés de `/cabinet/waiting-room` (déjà
  /// appelé par [getSummary]) ; la durée prévue vient de `/cabinet/appointments`
  /// par jointure sur `appointmentId`.
  final String? nextPatientName;
  final String? nextPatientReason;
  final DateTime? nextPatientAppointmentTime;
  final int? nextPatientDurationMinutes;
  final int? nextPatientWaitingMinutes;

  /// Allergie, plan de traitement et dernière visite ne sont pas exposés par
  /// les endpoints agrégés ci-dessus — restent `null` jusqu'à un ticket
  /// domaine dédié (jointure dossier patient côté back).
  final String? nextPatientAllergyLabel;
  final int? nextPatientTreatmentPlanCents;
  final DateTime? nextPatientLastVisitAt;

  const ProDashboardSummary({
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
    this.nextPatientAllergyLabel,
    this.nextPatientTreatmentPlanCents,
    this.nextPatientLastVisitAt,
  });
}

abstract class CabinetDashboardRepository {
  Future<Either<Failure, ProDashboardSummary>> getSummary();
}

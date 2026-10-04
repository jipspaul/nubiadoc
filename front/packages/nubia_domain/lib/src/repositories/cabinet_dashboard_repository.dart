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

  /// Identifiants du RDV et du patient en attente (#6241) — indispensables
  /// aux actions du hero : « Démarrer la consultation » doit appeler
  /// `POST /cabinet/appointments/<nextPatientAppointmentId>/start` et
  /// « Ouvrir le dossier » doit ouvrir `/patients/<nextPatientPatientId>`,
  /// plutôt que d'atterrir sur des listes génériques sans patient ciblé.
  final String? nextPatientAppointmentId;
  final String? nextPatientPatientId;

  /// Allergie, plan de traitement en cours et dernière visite du patient
  /// suivant (#7962) — jointure sur `GET .../medical-record`, `GET
  /// .../treatment-plans` et `GET /cabinet/patients/:id`. `null` quand le
  /// dossier ne porte pas l'alerte/le plan/la visite correspondant.
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
    this.nextPatientAppointmentId,
    this.nextPatientPatientId,
    this.nextPatientAllergyLabel,
    this.nextPatientTreatmentPlanCents,
    this.nextPatientLastVisitAt,
  });
}

abstract class CabinetDashboardRepository {
  Future<Either<Failure, ProDashboardSummary>> getSummary({
    String? practitionerId,
  });
}

import 'package:equatable/equatable.dart';

enum AppointmentStatus {
  requested,
  confirmed,
  checkedIn,
  inProgress,
  cancelled,
  completed,
  noShow,
}

enum AppointmentType { inPerson, teleconsult }

class Appointment extends Equatable {
  final String id;
  final String cabinetId;
  final String practitionerName;
  final String practitionerSpecialty;
  final DateTime startsAt;
  final Duration duration;
  final String motif;
  final AppointmentStatus status;
  final AppointmentType type;
  final String? cabinetAddress;
  final String? cabinetPhone;
  // Requis pour proposer une nouvelle date/heure avec le même praticien
  // (GET /providers/:id/availability) — vide si l'API ne l'expose pas.
  final String practitionerId;
  // #5563/#5593 : `beneficiary.is_self` distingue un RDV pris par le tuteur
  // pour lui-même d'un RDV pris pour un dépendant (on_behalf_of) — sans ça,
  // « Mes RDV » ne peut pas afficher pour qui est chaque rendez-vous.
  // `beneficiaryName` est null quand `beneficiaryIsSelf` est true (l'API ne
  // renvoie pas de nom dans ce cas, redondant avec le compte du tuteur).
  final bool beneficiaryIsSelf;
  final String? beneficiaryName;
  // #5272 : frais de non-présentation (charte du cabinet), facturés au
  // patient sur un RDV `noShow` — null si l'API ne les expose pas (le
  // montant ne doit jamais être codé en dur côté front).
  final int? noShowFeeCents;
  // #5271 : pilotage des chips de synthèse documentaire sur l'historique
  // (compte-rendu / ordonnance(s)) — défauts « aucun document » pour rester
  // rétrocompatible tant que l'API ne les expose pas.
  final bool hasReport;
  final int prescriptionCount;

  const Appointment({
    required this.id,
    required this.cabinetId,
    required this.practitionerName,
    required this.practitionerSpecialty,
    required this.startsAt,
    required this.duration,
    required this.motif,
    required this.status,
    this.type = AppointmentType.inPerson,
    this.cabinetAddress,
    this.cabinetPhone,
    this.practitionerId = '',
    this.beneficiaryIsSelf = true,
    this.beneficiaryName,
    this.noShowFeeCents,
    this.hasReport = false,
    this.prescriptionCount = 0,
  });

  bool get isUpcoming =>
      startsAt.isAfter(DateTime.now()) && status == AppointmentStatus.confirmed;

  /// #3804 : le backend autorise l'annulation tant que le statut est
  /// requested/confirmed/checkedIn (la classe majoritaire des RDV patient
  /// est `requested`, or `canCancel` ne couvrait avant que `confirmed`) —
  /// bloquée uniquement dans la fenêtre des 2h précédant le RDV, sauf si
  /// déjà `checkedIn` (sortie de file possible à tout moment) — cf.
  /// `cancel_appointment` (api/src/appointments.rs).
  bool get canCancel {
    final cancellableStatus = status == AppointmentStatus.requested ||
        status == AppointmentStatus.confirmed ||
        status == AppointmentStatus.checkedIn;
    if (!cancellableStatus) return false;
    if (status == AppointmentStatus.checkedIn) return true;
    final now = DateTime.now();
    final tooLate = now.isBefore(startsAt) &&
        !now.isBefore(startsAt.subtract(const Duration(hours: 2)));
    return !tooLate;
  }

  /// #3804 : le backend autorise la reprogrammation tant que le statut est
  /// requested/confirmed, bloquée à moins de 24h du RDV — cf.
  /// `reschedule_appointment` (api/src/appointments.rs).
  bool get canModify {
    final modifiableStatus = status == AppointmentStatus.requested ||
        status == AppointmentStatus.confirmed;
    if (!modifiableStatus) return false;
    return DateTime.now()
        .isBefore(startsAt.subtract(const Duration(hours: 24)));
  }

  @override
  List<Object?> get props => [id, status, startsAt];
}

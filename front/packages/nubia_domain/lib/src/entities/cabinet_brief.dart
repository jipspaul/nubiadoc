import 'package:equatable/equatable.dart';

/// Un RDV listé dans un brief cabinet (#7191). Source :
/// `GET /v1/cabinet/briefs/{day,week,prostheses}`.
class BriefAppointmentItem extends Equatable {
  final String id;
  final String startsAt;
  final String patientId;
  final String patientDisplayName;
  final String? motif;
  final String status;

  const BriefAppointmentItem({
    required this.id,
    required this.startsAt,
    required this.patientId,
    required this.patientDisplayName,
    this.motif,
    required this.status,
  });

  @override
  List<Object?> get props => [id];
}

/// Les RDV d'un praticien sur la période du brief.
class BriefPractitionerAppointments extends Equatable {
  final String practitionerId;
  final String? practitionerDisplayName;
  final List<BriefAppointmentItem> appointments;

  const BriefPractitionerAppointments({
    required this.practitionerId,
    this.practitionerDisplayName,
    required this.appointments,
  });

  @override
  List<Object?> get props => [practitionerId, appointments];
}

/// Un patient vu pour la première fois sur la période du brief.
class BriefNewPatient extends Equatable {
  final String patientId;
  final String patientDisplayName;
  final String appointmentId;
  final String startsAt;

  const BriefNewPatient({
    required this.patientId,
    required this.patientDisplayName,
    required this.appointmentId,
    required this.startsAt,
  });

  @override
  List<Object?> get props => [patientId, appointmentId];
}

/// Un motif de RDV agrégé sur la période du brief.
class BriefPlannedAct extends Equatable {
  final String motif;
  final int count;

  const BriefPlannedAct({required this.motif, required this.count});

  @override
  List<Object?> get props => [motif];
}

/// Une prothèse à poser sur la période du brief.
class BriefProsthesis extends Equatable {
  final String id;
  final String patientId;
  final String patientDisplayName;
  final String appointmentId;
  final String appointmentStartsAt;
  final String? toothFdi;
  final String? workNature;
  final String labName;
  final String status;

  const BriefProsthesis({
    required this.id,
    required this.patientId,
    required this.patientDisplayName,
    required this.appointmentId,
    required this.appointmentStartsAt,
    this.toothFdi,
    this.workNature,
    required this.labName,
    required this.status,
  });

  @override
  List<Object?> get props => [id];
}

/// Une tâche ouverte du cabinet listée dans le brief.
class BriefOpenTask extends Equatable {
  final String id;
  final String title;
  final String? assigneeDisplayName;
  final String? patientDisplayName;
  final String? dueDate;

  const BriefOpenTask({
    required this.id,
    required this.title,
    this.assigneeDisplayName,
    this.patientDisplayName,
    this.dueDate,
  });

  @override
  List<Object?> get props => [id];
}

/// Le brief complet du cabinet (#7191/#7192) : RDV par praticien, nouveaux
/// patients, actes prévus, prothèses à poser, tâches ouvertes. Source :
/// `GET /v1/cabinet/briefs/{day,week,prostheses}`.
class CabinetBrief extends Equatable {
  /// "day" | "week" | "prostheses".
  final String view;
  final String rangeStart;
  final String rangeEnd;
  final List<BriefPractitionerAppointments> appointmentsByPractitioner;
  final List<BriefNewPatient> newPatients;
  final List<BriefPlannedAct> plannedActs;
  final List<BriefProsthesis> prosthesesToFit;
  final List<BriefOpenTask> openTasks;

  const CabinetBrief({
    required this.view,
    required this.rangeStart,
    required this.rangeEnd,
    required this.appointmentsByPractitioner,
    required this.newPatients,
    required this.plannedActs,
    required this.prosthesesToFit,
    required this.openTasks,
  });

  @override
  List<Object?> get props => [
        view,
        rangeStart,
        rangeEnd,
        appointmentsByPractitioner,
        newPatients,
        plannedActs,
        prosthesesToFit,
        openTasks,
      ];
}

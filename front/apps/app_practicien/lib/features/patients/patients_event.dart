import 'package:equatable/equatable.dart';
import 'package:nubia_domain/nubia_domain.dart';

abstract class PatientsEvent extends Equatable {
  const PatientsEvent();

  @override
  List<Object?> get props => [];
}

class PatientsLoadRequested extends PatientsEvent {
  const PatientsLoadRequested();
}

/// Recherche serveur (#4043) — remplace le filtrage en mémoire, qui ne
/// scale plus au-delà de quelques centaines de dossiers. Le debounce est
/// géré côté UI (patients_page.dart), pas ici.
class PatientsSearchChanged extends PatientsEvent {
  final String query;
  const PatientsSearchChanged(this.query);

  @override
  List<Object?> get props => [query];
}

class PatientsDetailLoadRequested extends PatientsEvent {
  final String id;
  const PatientsDetailLoadRequested(this.id);

  @override
  List<Object?> get props => [id];
}

class PatientsNotesUpdateRequested extends PatientsEvent {
  final String id;
  final String notes;
  const PatientsNotesUpdateRequested(this.id, this.notes);

  @override
  List<Object?> get props => [id, notes];
}

class PatientExportPdfRequested extends PatientsEvent {
  final CabinetPatient patient;
  const PatientExportPdfRequested(this.patient);

  @override
  List<Object?> get props => [patient];
}

/// « Démarrer une consultation » depuis l'en-tête de la fiche patient (#8040,
/// maquette design-v2 §.hb) : démarre le RDV déjà identifié comme éligible
/// par [startableAppointment] (patients_page.dart), même garde côté bloc
/// que `AgendaConsultationStartRequested`/`DashboardConsultationStartRequested`.
class PatientsStartConsultationRequested extends PatientsEvent {
  final String appointmentId;
  const PatientsStartConsultationRequested(this.appointmentId);

  @override
  List<Object?> get props => [appointmentId];
}

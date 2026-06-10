import 'package:equatable/equatable.dart';

import '../bloc/appointment_event.dart';
import '../models/appointment.dart';

sealed class AppointmentState extends Equatable {
  const AppointmentState();

  @override
  List<Object?> get props => [];
}

final class AppointmentInitial extends AppointmentState {
  const AppointmentInitial();
}

final class AppointmentLoading extends AppointmentState {
  const AppointmentLoading();
}

/// Liste chargée avec l'onglet actif.
final class AppointmentListLoaded extends AppointmentState {
  const AppointmentListLoaded(this.appointments,
      {this.tab = AppointmentTab.upcoming});

  final List<Appointment> appointments;
  final AppointmentTab tab;

  @override
  List<Object?> get props => [appointments, tab];
}

/// Détail chargé.
final class AppointmentDetailLoaded extends AppointmentState {
  const AppointmentDetailLoaded(this.appointment);

  final Appointment appointment;

  @override
  List<Object?> get props => [appointment];
}

/// Annulation en cours (affiche spinner, liste en arrière-plan).
final class AppointmentCancelling extends AppointmentState {
  const AppointmentCancelling(this.appointments);

  final List<Appointment> appointments;

  @override
  List<Object?> get props => [appointments];
}

/// RDV booké avec succès.
final class AppointmentBooked extends AppointmentState {
  const AppointmentBooked(this.appointment);

  final Appointment appointment;

  @override
  List<Object?> get props => [appointment];
}

final class AppointmentError extends AppointmentState {
  const AppointmentError(this.message);

  final String message;

  @override
  List<Object?> get props => [message];
}


import 'package:equatable/equatable.dart';
import 'package:nubia_domain/nubia_domain.dart';

abstract class AgendaEvent extends Equatable {
  const AgendaEvent();

  @override
  List<Object?> get props => [];
}

class AgendaLoadRequested extends AgendaEvent {
  final DateTime weekStart;
  const AgendaLoadRequested({required this.weekStart});

  @override
  List<Object?> get props => [weekStart];
}

class AgendaAppointmentCreateRequested extends AgendaEvent {
  final CabinetAppointment appointment;
  const AgendaAppointmentCreateRequested({required this.appointment});

  @override
  List<Object?> get props => [appointment];
}

class AgendaAppointmentConfirmRequested extends AgendaEvent {
  final String appointmentId;
  const AgendaAppointmentConfirmRequested({required this.appointmentId});

  @override
  List<Object?> get props => [appointmentId];
}

class AgendaAppointmentCheckinRequested extends AgendaEvent {
  final String appointmentId;
  const AgendaAppointmentCheckinRequested({required this.appointmentId});

  @override
  List<Object?> get props => [appointmentId];
}

class AgendaAppointmentRescheduleRequested extends AgendaEvent {
  final String appointmentId;
  final DateTime newStartsAt;
  const AgendaAppointmentRescheduleRequested({
    required this.appointmentId,
    required this.newStartsAt,
  });

  @override
  List<Object?> get props => [appointmentId, newStartsAt];
}

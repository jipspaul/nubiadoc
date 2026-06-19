import 'package:equatable/equatable.dart';

abstract class AgendaEvent extends Equatable {
  const AgendaEvent();

  @override
  List<Object?> get props => [];
}

class AgendaLoadRequested extends AgendaEvent {
  const AgendaLoadRequested({required this.weekStart});
  final DateTime weekStart;

  @override
  List<Object?> get props => [weekStart];
}

class AgendaWeekChanged extends AgendaEvent {
  const AgendaWeekChanged({required this.weekStart});
  final DateTime weekStart;

  @override
  List<Object?> get props => [weekStart];
}

class AgendaAppointmentConfirmRequested extends AgendaEvent {
  const AgendaAppointmentConfirmRequested({required this.appointmentId});
  final String appointmentId;

  @override
  List<Object?> get props => [appointmentId];
}

class AgendaConsultationStartRequested extends AgendaEvent {
  const AgendaConsultationStartRequested({required this.appointmentId});
  final String appointmentId;

  @override
  List<Object?> get props => [appointmentId];
}

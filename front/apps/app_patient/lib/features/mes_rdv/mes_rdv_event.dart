import 'package:equatable/equatable.dart';
import 'package:nubia_domain/nubia_domain.dart';

abstract class MesRdvEvent extends Equatable {
  const MesRdvEvent();

  @override
  List<Object?> get props => [];
}

class MesRdvLoadRequested extends MesRdvEvent {
  const MesRdvLoadRequested();
}

class MesRdvCancelRequested extends MesRdvEvent {
  final Appointment appointment;
  const MesRdvCancelRequested(this.appointment);

  @override
  List<Object?> get props => [appointment];
}

class MesRdvCheckinRequested extends MesRdvEvent {
  final String appointmentId;
  const MesRdvCheckinRequested(this.appointmentId);

  @override
  List<Object?> get props => [appointmentId];
}

import 'package:nubia_domain/nubia_domain.dart';

abstract class AppointmentsState {
  const AppointmentsState();
}

class AppointmentsInitial extends AppointmentsState {
  const AppointmentsInitial();

  @override
  bool operator ==(Object other) => other is AppointmentsInitial;

  @override
  int get hashCode => runtimeType.hashCode;
}

class AppointmentsLoading extends AppointmentsState {
  const AppointmentsLoading();

  @override
  bool operator ==(Object other) => other is AppointmentsLoading;

  @override
  int get hashCode => runtimeType.hashCode;
}

class AppointmentSuccess extends AppointmentsState {
  const AppointmentSuccess(this.appointment);

  final CabinetAppointment appointment;

  @override
  bool operator ==(Object other) =>
      other is AppointmentSuccess && other.appointment == appointment;

  @override
  int get hashCode => appointment.hashCode;
}

class AppointmentsLoaded extends AppointmentsState {
  const AppointmentsLoaded(this.appointments);

  final List<CabinetAppointment> appointments;

  @override
  bool operator ==(Object other) =>
      other is AppointmentsLoaded &&
      other.appointments.length == appointments.length &&
      List.generate(
        appointments.length,
        (i) => other.appointments[i] == appointments[i],
      ).every((b) => b);

  @override
  int get hashCode => Object.hashAll(appointments);
}

class AppointmentsError extends AppointmentsState {
  const AppointmentsError(this.message);

  final String message;

  @override
  bool operator ==(Object other) =>
      other is AppointmentsError && other.message == message;

  @override
  int get hashCode => message.hashCode;
}

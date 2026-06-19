import 'package:nubia_domain/nubia_domain.dart';

abstract class AppointmentsEvent {
  const AppointmentsEvent();
}

class AppointmentCreateRequested extends AppointmentsEvent {
  const AppointmentCreateRequested({required this.appointment});

  final CabinetAppointment appointment;
}

class AppointmentConfirmRequested extends AppointmentsEvent {
  const AppointmentConfirmRequested({required this.appointmentId});

  final String appointmentId;
}

class AppointmentRescheduleRequested extends AppointmentsEvent {
  const AppointmentRescheduleRequested({
    required this.appointmentId,
    required this.newStartsAt,
  });

  final String appointmentId;
  final DateTime newStartsAt;
}

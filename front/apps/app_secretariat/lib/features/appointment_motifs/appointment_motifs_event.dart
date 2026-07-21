abstract class AppointmentMotifsEvent {
  const AppointmentMotifsEvent();
}

class AppointmentMotifsLoadRequested extends AppointmentMotifsEvent {
  const AppointmentMotifsLoadRequested();
}

class AppointmentMotifsCreateRequested extends AppointmentMotifsEvent {
  const AppointmentMotifsCreateRequested({
    required this.label,
    this.defaultDurationMinutes,
  });

  final String label;
  final int? defaultDurationMinutes;
}

class AppointmentMotifsUpdateRequested extends AppointmentMotifsEvent {
  const AppointmentMotifsUpdateRequested({
    required this.id,
    required this.label,
    this.defaultDurationMinutes,
  });

  final String id;
  final String label;
  final int? defaultDurationMinutes;
}

class AppointmentMotifsDeleteRequested extends AppointmentMotifsEvent {
  const AppointmentMotifsDeleteRequested(this.id);

  final String id;
}

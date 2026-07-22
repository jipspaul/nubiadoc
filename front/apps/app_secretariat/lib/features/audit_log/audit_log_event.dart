abstract class AuditLogEvent {
  const AuditLogEvent();
}

class AuditLogLoadRequested extends AuditLogEvent {
  const AuditLogLoadRequested({this.from, this.to, this.entity});

  final DateTime? from;
  final DateTime? to;
  final String? entity;
}

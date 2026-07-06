abstract class AdminSecretiariatsEvent {
  const AdminSecretiariatsEvent();
}

class AdminSecretiariatsLoadRequested extends AdminSecretiariatsEvent {
  const AdminSecretiariatsLoadRequested();
}

class AdminSecretiariatsInviteRequested extends AdminSecretiariatsEvent {
  const AdminSecretiariatsInviteRequested({
    required this.name,
    required this.email,
  });

  final String name;
  final String email;
}

abstract class AdminSecretariatsEvent {
  const AdminSecretariatsEvent();
}

class AdminSecretariatsLoadRequested extends AdminSecretariatsEvent {
  const AdminSecretariatsLoadRequested();
}

class AdminSecretariatsInviteRequested extends AdminSecretariatsEvent {
  const AdminSecretariatsInviteRequested({
    required this.name,
    required this.email,
  });

  final String name;
  final String email;
}

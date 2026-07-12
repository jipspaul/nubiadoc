import 'package:nubia_domain/nubia_domain.dart';

abstract class AdminMembresEvent {
  const AdminMembresEvent();
}

class AdminMembresLoadRequested extends AdminMembresEvent {
  const AdminMembresLoadRequested();
}

class AdminMembresInviteRequested extends AdminMembresEvent {
  const AdminMembresInviteRequested({
    required this.email,
    required this.role,
    required this.firstName,
    required this.lastName,
  });

  final String email;
  final MemberRole role;
  final String firstName;
  final String lastName;
}

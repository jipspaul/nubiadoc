import 'package:equatable/equatable.dart';

/// Lien d'invitation copiable par rôle (#7148).
/// Source : POST /v1/cabinet/invite-links
class CabinetInviteLink extends Equatable {
  final String id;
  final String role;
  final String token;
  final String url;
  final int maxUses;
  final DateTime expiresAt;

  const CabinetInviteLink({
    required this.id,
    required this.role,
    required this.token,
    required this.url,
    required this.maxUses,
    required this.expiresAt,
  });

  @override
  List<Object?> get props => [id];
}

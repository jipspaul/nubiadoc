/// Membre actif d'un secrétariat (#6862), tel que renvoyé par
/// `GET /v1/cabinet/secretariats/:id/members` — accessible à tout membre pro
/// du cabinet (`ProMemberClaims`, pas de restriction admin, contrairement à
/// `GET /v1/cabinet/members`). L'endpoint ne porte pas encore le prénom/nom :
/// cette entité ne permet donc qu'un compte, pas un affichage nominatif.
class SecretariatMember {
  const SecretariatMember({
    required this.userId,
    required this.role,
    required this.active,
  });

  final String userId;
  final String role;
  final bool active;
}

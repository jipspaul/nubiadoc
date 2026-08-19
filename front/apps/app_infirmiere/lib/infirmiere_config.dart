import 'package:nubia_core/nubia_core.dart';

/// Constantes de l'app infirmière. [role] amorce une [AuthSession] stub
/// (`kind:pro`, `role:nurse`) tant que `GET /v1/me` + select-nurse-context ne
/// sont pas câblés côté app (TODO) — le backend expose déjà les deux.
class InfirmiereConfig {
  const InfirmiereConfig._();

  static const String appTitle = 'Nubia · Infirmier·ère';
  static const String spaceLabel = 'Espace infirmier — soins à domicile';
  static const ProRole role = ProRole.nurse;
}

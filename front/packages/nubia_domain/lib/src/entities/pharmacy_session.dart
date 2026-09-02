import 'package:equatable/equatable.dart';

/// Appartenance de l'utilisateur connecté à une pharmacie
/// (`pharmacy_memberships` de `GET /v1/me`, tokens `kind:"pro"`).
class PharmacyMembership extends Equatable {
  final String pharmacyId;

  /// `pharmacist` | `preparator` | `admin`.
  final String role;

  /// Raison sociale de la pharmacie (#6170) — vide si non renseignée côté API.
  final String name;

  const PharmacyMembership({
    required this.pharmacyId,
    required this.role,
    this.name = '',
  });

  @override
  List<Object?> get props => [pharmacyId, role, name];
}

/// Contexte pharmacie actif après `POST /v1/auth/select-pharmacy-context`
/// (le JWT `kind:"pharma"` est persisté par la couche data, jamais exposé ici).
class PharmacyContext extends Equatable {
  final String pharmacyId;
  final String role;

  /// Raison sociale de la pharmacie (#6170) — vide si non renseignée côté API.
  final String name;

  const PharmacyContext({
    required this.pharmacyId,
    required this.role,
    this.name = '',
  });

  @override
  List<Object?> get props => [pharmacyId, role, name];
}

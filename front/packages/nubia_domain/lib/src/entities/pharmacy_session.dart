import 'package:equatable/equatable.dart';

/// Appartenance de l'utilisateur connecté à une pharmacie
/// (`pharmacy_memberships` de `GET /v1/me`, tokens `kind:"pro"`).
class PharmacyMembership extends Equatable {
  final String pharmacyId;

  /// `pharmacist` | `preparator` | `admin`.
  final String role;

  const PharmacyMembership({required this.pharmacyId, required this.role});

  @override
  List<Object?> get props => [pharmacyId, role];
}

/// Contexte pharmacie actif après `POST /v1/auth/select-pharmacy-context`
/// (le JWT `kind:"pharma"` est persisté par la couche data, jamais exposé ici).
class PharmacyContext extends Equatable {
  final String pharmacyId;
  final String role;

  const PharmacyContext({required this.pharmacyId, required this.role});

  @override
  List<Object?> get props => [pharmacyId, role];
}

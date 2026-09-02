import 'package:nubia_domain/nubia_domain.dart';

/// Une entrée de `pharmacy_memberships` dans `GET /v1/me`.
class PharmacyMembershipDto {
  final String pharmacyId;
  final String role;
  final String name;

  const PharmacyMembershipDto({
    required this.pharmacyId,
    required this.role,
    this.name = '',
  });

  factory PharmacyMembershipDto.fromJson(Map<String, dynamic> json) {
    return PharmacyMembershipDto(
      pharmacyId: json['pharmacy_id'] as String? ?? '',
      role: json['role'] as String? ?? '',
      name: json['pharmacy_name'] as String? ?? '',
    );
  }

  PharmacyMembership toDomain() =>
      PharmacyMembership(pharmacyId: pharmacyId, role: role, name: name);
}

/// Réponse de `POST /v1/auth/select-pharmacy-context`.
class SelectPharmacyContextDto {
  final String accessToken;
  final String pharmacyId;
  final String role;
  final String pharmacyName;

  const SelectPharmacyContextDto({
    required this.accessToken,
    required this.pharmacyId,
    required this.role,
    this.pharmacyName = '',
  });

  factory SelectPharmacyContextDto.fromJson(Map<String, dynamic> json) {
    final context = json['context'] as Map<String, dynamic>? ?? const {};
    return SelectPharmacyContextDto(
      accessToken: json['access_token'] as String? ?? '',
      pharmacyId: context['pharmacy_id'] as String? ?? '',
      role: context['role'] as String? ?? '',
      pharmacyName: context['pharmacy_name'] as String? ?? '',
    );
  }

  PharmacyContext toDomain() =>
      PharmacyContext(pharmacyId: pharmacyId, role: role, name: pharmacyName);
}

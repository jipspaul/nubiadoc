import 'package:nubia_domain/nubia_domain.dart';

/// Une entrée de `pharmacy_memberships` dans `GET /v1/me`.
class PharmacyMembershipDto {
  final String pharmacyId;
  final String role;

  const PharmacyMembershipDto({required this.pharmacyId, required this.role});

  factory PharmacyMembershipDto.fromJson(Map<String, dynamic> json) {
    return PharmacyMembershipDto(
      pharmacyId: json['pharmacy_id'] as String? ?? '',
      role: json['role'] as String? ?? '',
    );
  }

  PharmacyMembership toDomain() =>
      PharmacyMembership(pharmacyId: pharmacyId, role: role);
}

/// Réponse de `POST /v1/auth/select-pharmacy-context`.
class SelectPharmacyContextDto {
  final String accessToken;
  final String pharmacyId;
  final String role;

  const SelectPharmacyContextDto({
    required this.accessToken,
    required this.pharmacyId,
    required this.role,
  });

  factory SelectPharmacyContextDto.fromJson(Map<String, dynamic> json) {
    final context = json['context'] as Map<String, dynamic>? ?? const {};
    return SelectPharmacyContextDto(
      accessToken: json['access_token'] as String? ?? '',
      pharmacyId: context['pharmacy_id'] as String? ?? '',
      role: context['role'] as String? ?? '',
    );
  }

  PharmacyContext toDomain() =>
      PharmacyContext(pharmacyId: pharmacyId, role: role);
}

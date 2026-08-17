import 'package:nubia_domain/src/entities/pharmacy.dart';

class PharmacyDto {
  final String id;
  final String name;
  final String? address;
  final String? phone;
  final double? distanceM;

  const PharmacyDto({
    required this.id,
    required this.name,
    this.address,
    this.phone,
    this.distanceM,
  });

  factory PharmacyDto.fromJson(Map<String, dynamic> json) {
    return PharmacyDto(
      id: json['id'] as String,
      name: (json['raison_sociale'] ?? json['name']) as String? ?? 'Pharmacie',
      address: formatAddress(json['address']),
      phone: json['phone'] as String?,
      distanceM: (json['distance_m'] as num?)?.toDouble(),
    );
  }

  /// Le back renvoie l'adresse en jsonb (`{line1, city, ...}`) ; on tolère
  /// aussi une chaîne déjà formatée par robustesse.
  static String? formatAddress(dynamic rawAddress) {
    final address = rawAddress is String
        ? rawAddress
        : rawAddress is Map<String, dynamic>
            ? [
                rawAddress['line1'],
                rawAddress['postal_code'],
                rawAddress['city']
              ].whereType<String>().where((part) => part.isNotEmpty).join(', ')
            : null;
    return address != null && address.isNotEmpty ? address : null;
  }

  Pharmacy toDomain() => Pharmacy(
        id: id,
        name: name,
        address: address,
        phone: phone,
        distanceM: distanceM,
      );
}

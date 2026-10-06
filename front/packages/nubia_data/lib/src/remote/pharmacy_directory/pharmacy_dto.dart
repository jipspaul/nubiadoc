import 'package:nubia_domain/src/entities/pharmacy.dart';

class PharmacyDto {
  final String id;
  final String name;
  final String? address;
  final String? phone;
  final double? distanceM;
  final Map<String, String>? openingHours;

  const PharmacyDto({
    required this.id,
    required this.name,
    this.address,
    this.phone,
    this.distanceM,
    this.openingHours,
  });

  factory PharmacyDto.fromJson(Map<String, dynamic> json) {
    return PharmacyDto(
      id: json['id'] as String,
      name: (json['raison_sociale'] ?? json['name']) as String? ?? 'Pharmacie',
      address: formatAddress(json['address']),
      phone: json['phone'] as String?,
      distanceM: (json['distance_m'] as num?)?.toDouble(),
      openingHours: formatOpeningHours(json['opening_hours']),
    );
  }

  /// Le back renvoie les horaires en jsonb (`{jour_abrégé: "HH:MM-HH:MM"}`) ;
  /// clé/valeur non-chaîne ignorées (défensif, #8061).
  static Map<String, String>? formatOpeningHours(dynamic raw) {
    if (raw is! Map) return null;
    final hours = <String, String>{};
    for (final entry in raw.entries) {
      if (entry.key is String && entry.value is String) {
        hours[entry.key as String] = entry.value as String;
      }
    }
    return hours.isEmpty ? null : hours;
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
        openingHours: openingHours,
      );
}

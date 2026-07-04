import 'package:equatable/equatable.dart';

/// Pharmacie de l'annuaire public (GET /v1/pharmacies).
class Pharmacy extends Equatable {
  final String id;
  final String name;
  final String? address;
  final String? phone;

  /// Distance en mètres depuis le point de recherche (si lat/lng fournis).
  final double? distanceM;

  const Pharmacy({
    required this.id,
    required this.name,
    this.address,
    this.phone,
    this.distanceM,
  });

  double? get distanceKm => distanceM == null ? null : distanceM! / 1000.0;

  @override
  List<Object?> get props => [id];
}

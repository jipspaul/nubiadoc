import 'package:equatable/equatable.dart';

/// Résultat d'une recherche de praticien (GET /v1/search/providers).
class ProviderResult extends Equatable {
  final String id;
  final String displayName;
  final String specialty;
  final String? address;
  final double? distanceKm;
  final double? lat;
  final double? lng;
  final double? ratingAvg;
  final DateTime? nextSlotAt;

  /// Conventionnement (`'1'`/`'2'`/`'3'`) — panneau de filtres patient
  /// (#5359, groupe « Tarifs »).
  final String? sector;
  final bool? tiersPayant;
  final bool? pmr;
  final bool? acceptsNewPatients;

  const ProviderResult({
    required this.id,
    required this.displayName,
    required this.specialty,
    this.address,
    this.distanceKm,
    this.lat,
    this.lng,
    this.ratingAvg,
    this.nextSlotAt,
    this.sector,
    this.tiersPayant,
    this.pmr,
    this.acceptsNewPatients,
  });

  bool get hasLocation => lat != null && lng != null;

  @override
  List<Object?> get props => [id];
}

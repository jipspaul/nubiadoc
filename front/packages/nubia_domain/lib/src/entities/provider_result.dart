import 'package:equatable/equatable.dart';

/// Résultat d'une recherche de praticien (GET /v1/search/providers).
class ProviderResult extends Equatable {
  final String id;
  final String displayName;
  final String specialty;
  final String? address;
  final double? distanceKm;

  const ProviderResult({
    required this.id,
    required this.displayName,
    required this.specialty,
    this.address,
    this.distanceKm,
  });

  @override
  List<Object?> get props => [id];
}

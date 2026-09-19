import 'package:equatable/equatable.dart';

/// Correspondant de l'annuaire du cabinet (#7194/#7195, DP-F8.b/a) — nom,
/// spécialité, coordonnées, RPPS. Source : `GET /v1/cabinet/correspondents`.
/// Distinct d'un correspondant patient en texte libre (`patient_correspondent`) :
/// cette entité est partagée par le cabinet et alimente les stats
/// d'adressage (`referred_by_correspondent_id`).
class CabinetCorrespondent extends Equatable {
  final String id;
  final String displayName;
  final String? specialty;
  final String? email;
  final String? phone;
  final String? address;
  final String? rpps;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  const CabinetCorrespondent({
    required this.id,
    required this.displayName,
    this.specialty,
    this.email,
    this.phone,
    this.address,
    this.rpps,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
  });

  @override
  List<Object?> get props => [id];
}

/// Statistiques d'adressage d'un correspondant (#7193) — patients adressés,
/// CA facturé, courriers envoyés. Source :
/// `GET /v1/cabinet/correspondents/:id/stats`.
class CorrespondentStats extends Equatable {
  final int referredPatientsCount;
  final int billedRevenueCents;
  final int lettersSentCount;

  const CorrespondentStats({
    required this.referredPatientsCount,
    required this.billedRevenueCents,
    required this.lettersSentCount,
  });

  @override
  List<Object?> get props => [
        referredPatientsCount,
        billedRevenueCents,
        lettersSentCount,
      ];
}

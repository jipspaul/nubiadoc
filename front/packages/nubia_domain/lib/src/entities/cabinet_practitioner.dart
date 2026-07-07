import 'package:equatable/equatable.dart';

/// Praticien du cabinet (roster), vu côté secrétariat.
/// Source : GET /v1/cabinet/agenda → champ `practitioners`.
///
/// Aucune donnée clinique : seulement l'identité et la spécialité, nécessaires
/// pour rattacher un créneau / un RDV au bon médecin.
class CabinetPractitioner extends Equatable {
  final String id;
  final String displayName;
  final String? specialite;

  const CabinetPractitioner({
    required this.id,
    required this.displayName,
    this.specialite,
  });

  @override
  List<Object?> get props => [id, displayName, specialite];
}

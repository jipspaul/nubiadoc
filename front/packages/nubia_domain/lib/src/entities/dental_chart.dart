import 'package:equatable/equatable.dart';

/// État d'une dent dans l'odontogramme (#4047).
/// `status`/`plan` : vocabulaire fermé côté API (`TOOTH_STATUSES`,
/// `api/src/dental_chart.rs`) — sain, present, carie, obture, couronne,
/// bridge, implant, absent, a_extraire, devitalise, fracture.
class ToothState extends Equatable {
  final String status;
  final String? plan;
  final String? notes;

  const ToothState({required this.status, this.plan, this.notes});

  @override
  List<Object?> get props => [status, plan, notes];
}

/// Odontogramme complet d'un patient. `teeth` : clé = code FDI ("11".."48"
/// dentition permanente, "51".."85" dentition lait), valeur = état de la dent.
/// Source : `GET/PUT /v1/cabinet/patients/:id/dental-chart`.
///
/// `updatedAt` est `null` tant qu'aucun odontogramme n'a été enregistré
/// pour ce patient : l'API renvoie alors `{ teeth: {}, updated_at: null }`
/// (`api/src/dental_chart.rs`, #4518). C'est l'état initial légitime d'un
/// patient neuf, pas une erreur (#6780).
class DentalChart extends Equatable {
  final Map<String, ToothState> teeth;
  final DateTime? updatedAt;

  const DentalChart({required this.teeth, this.updatedAt});

  /// Vrai quand aucun odontogramme n'a encore été enregistré.
  bool get isBlank => updatedAt == null;

  @override
  List<Object?> get props => [teeth, updatedAt];
}

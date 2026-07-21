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
class DentalChart extends Equatable {
  final Map<String, ToothState> teeth;
  final DateTime updatedAt;

  const DentalChart({required this.teeth, required this.updatedAt});

  @override
  List<Object?> get props => [teeth, updatedAt];
}

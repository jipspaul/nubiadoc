import 'package:nubia_domain/src/entities/dental_chart.dart';

class ToothStateDto {
  final String status;
  final String? plan;
  final String? notes;

  const ToothStateDto({required this.status, this.plan, this.notes});

  factory ToothStateDto.fromJson(Map<String, dynamic> json) => ToothStateDto(
        status: json['status'] as String,
        plan: json['plan'] as String?,
        notes: json['notes'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'status': status,
        if (plan != null) 'plan': plan,
        if (notes != null) 'notes': notes,
      };

  ToothState toDomain() => ToothState(status: status, plan: plan, notes: notes);

  factory ToothStateDto.fromDomain(ToothState s) =>
      ToothStateDto(status: s.status, plan: s.plan, notes: s.notes);
}

/// Réponse de `GET/PUT /v1/cabinet/patients/:id/dental-chart`.
///
/// `updated_at` est **nullable par contrat** (`Option<String>` dans
/// `api/src/dental_chart.rs`) : `null` = aucun odontogramme enregistré pour
/// ce patient. Le caster en `String` non-nullable transformait l'état
/// initial de tout patient neuf en `TypeError` → `ParseFailure` → écran
/// d'erreur « Réessayer » sans issue (#6780, QA-20260909-1).
class DentalChartDto {
  final Map<String, ToothStateDto> teeth;
  final String? updatedAt;

  const DentalChartDto({required this.teeth, this.updatedAt});

  factory DentalChartDto.fromJson(Map<String, dynamic> json) {
    final teethJson = json['teeth'] as Map<String, dynamic>? ?? const {};
    return DentalChartDto(
      teeth: teethJson.map(
        (k, v) =>
            MapEntry(k, ToothStateDto.fromJson(v as Map<String, dynamic>)),
      ),
      updatedAt: json['updated_at'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'teeth': teeth.map((k, v) => MapEntry(k, v.toJson())),
      };

  DentalChart toDomain() {
    final raw = updatedAt;
    return DentalChart(
      teeth: teeth.map((k, v) => MapEntry(k, v.toDomain())),
      updatedAt: raw == null ? null : DateTime.parse(raw),
    );
  }
}

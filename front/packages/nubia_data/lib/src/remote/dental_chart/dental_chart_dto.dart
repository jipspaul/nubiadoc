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

class DentalChartDto {
  final Map<String, ToothStateDto> teeth;
  final String updatedAt;

  const DentalChartDto({required this.teeth, required this.updatedAt});

  factory DentalChartDto.fromJson(Map<String, dynamic> json) {
    final teethJson = json['teeth'] as Map<String, dynamic>? ?? const {};
    return DentalChartDto(
      teeth: teethJson.map(
        (k, v) =>
            MapEntry(k, ToothStateDto.fromJson(v as Map<String, dynamic>)),
      ),
      updatedAt: json['updated_at'] as String,
    );
  }

  Map<String, dynamic> toJson() => {
        'teeth': teeth.map((k, v) => MapEntry(k, v.toJson())),
      };

  DentalChart toDomain() => DentalChart(
        teeth: teeth.map((k, v) => MapEntry(k, v.toDomain())),
        updatedAt: DateTime.parse(updatedAt),
      );
}

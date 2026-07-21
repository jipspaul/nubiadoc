import 'package:nubia_domain/src/entities/appointment_motif.dart';

class AppointmentMotifDto {
  final String id;
  final String label;
  final int? defaultDurationMinutes;

  const AppointmentMotifDto({
    required this.id,
    required this.label,
    this.defaultDurationMinutes,
  });

  factory AppointmentMotifDto.fromJson(Map<String, dynamic> json) =>
      AppointmentMotifDto(
        id: json['id'] as String,
        label: json['label'] as String,
        defaultDurationMinutes: json['default_duration_minutes'] as int?,
      );

  AppointmentMotif toDomain() => AppointmentMotif(
        id: id,
        label: label,
        defaultDurationMinutes: defaultDurationMinutes,
      );
}

import 'package:nubia_domain/src/entities/appointment_series.dart';

/// Réponse de `POST /v1/cabinet/appointments/series` (#4088) :
/// `{ recurrence_id, appointments: [{ id, recurrence_index, starts_at,
/// ends_at }] }`.
class AppointmentSeriesDto {
  final String recurrenceId;
  final List<AppointmentSeriesItemDto> appointments;

  const AppointmentSeriesDto({
    required this.recurrenceId,
    required this.appointments,
  });

  factory AppointmentSeriesDto.fromJson(Map<String, dynamic> json) {
    final items = json['appointments'] as List<dynamic>;
    return AppointmentSeriesDto(
      recurrenceId: json['recurrence_id'] as String,
      appointments: items
          .map((e) =>
              AppointmentSeriesItemDto.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  CreatedAppointmentSeries toDomain() => CreatedAppointmentSeries(
        recurrenceId: recurrenceId,
        appointments: appointments.map((e) => e.toDomain()).toList(),
      );
}

class AppointmentSeriesItemDto {
  final String id;
  final int recurrenceIndex;
  final String startsAt;
  final String endsAt;

  const AppointmentSeriesItemDto({
    required this.id,
    required this.recurrenceIndex,
    required this.startsAt,
    required this.endsAt,
  });

  factory AppointmentSeriesItemDto.fromJson(Map<String, dynamic> json) {
    return AppointmentSeriesItemDto(
      id: json['id'] as String,
      recurrenceIndex: (json['recurrence_index'] as num).toInt(),
      startsAt: json['starts_at'] as String,
      endsAt: json['ends_at'] as String,
    );
  }

  CreatedAppointmentSeriesItem toDomain() => CreatedAppointmentSeriesItem(
        id: id,
        recurrenceIndex: recurrenceIndex,
        startsAt: DateTime.parse(startsAt),
        endsAt: DateTime.parse(endsAt),
      );
}

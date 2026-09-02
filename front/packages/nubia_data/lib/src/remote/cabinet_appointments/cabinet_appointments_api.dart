import 'package:dio/dio.dart';
import 'package:nubia_core/src/network/api_client.dart';
import 'package:nubia_data/src/remote/cabinet_appointments/appointment_series_dto.dart';
import 'package:nubia_data/src/remote/cabinet_appointments/cabinet_appointments_dto.dart';
import 'package:nubia_domain/src/entities/appointment_series.dart';
import 'package:nubia_domain/src/entities/cabinet_appointment.dart';

class CabinetAppointmentsApi {
  final Dio _dio;

  CabinetAppointmentsApi(ApiClient client) : _dio = client.dio;

  Future<List<CabinetAppointmentDto>> list({int page = 1}) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/cabinet/appointments',
      queryParameters: {'page': page},
    );
    final data = response.data!['data'] as List<dynamic>;
    return data
        .map((e) => CabinetAppointmentDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<CabinetAppointmentDto> getById(String id) async {
    final response =
        await _dio.get<Map<String, dynamic>>('/cabinet/appointments/$id');
    return CabinetAppointmentDto.fromJson(response.data!);
  }

  Future<CabinetAppointmentDto> create(CabinetAppointment appointment) async {
    // Contrat back (`CreateCabinetAppointmentBody`) : { patient_id (UUID),
    // slot_id (UUID), notes? }. Le praticien / l'horaire / la durée sont résolus
    // côté serveur depuis le créneau — on ne les envoie pas (sinon 422).
    final data = <String, dynamic>{
      'patient_id': appointment.patientId,
      'slot_id': appointment.slotId,
      if (appointment.motif.trim().isNotEmpty) 'notes': appointment.motif,
    };
    final response = await _dio.post<Map<String, dynamic>>(
      '/cabinet/appointments',
      data: data,
    );
    // La réponse 201 ne contient que { appointment_id, status } — même shape
    // que /confirm. On parse via le factory dédié pour éviter une ParseFailure.
    return CabinetAppointmentDto.fromConfirmResponse(response.data!);
  }

  Future<CabinetAppointmentDto> update(CabinetAppointment appointment) async {
    final dto = CabinetAppointmentDto(
      id: appointment.id,
      cabinetId: appointment.cabinetId,
      patientId: appointment.patientId,
      patientName: appointment.patientName,
      practitionerId: appointment.practitionerId,
      practitionerName: appointment.practitionerName,
      startsAt: appointment.startsAt.toIso8601String(),
      durationMinutes: appointment.duration.inMinutes,
      motif: appointment.motif,
      status: appointment.status.name,
    );
    final response = await _dio.patch<Map<String, dynamic>>(
      '/cabinet/appointments/${appointment.id}',
      data: dto.toJson(),
    );
    return CabinetAppointmentDto.fromJson(response.data!);
  }

  Future<CabinetAppointmentDto> confirm(String id) async {
    final response = await _dio
        .post<Map<String, dynamic>>('/cabinet/appointments/$id/confirm');
    // La réponse 200 ne contient que { appointment_id, status } — pas le RDV
    // complet. On parse via le factory dédié pour éviter une ParseFailure.
    return CabinetAppointmentDto.fromConfirmResponse(response.data!);
  }

  Future<CabinetAppointmentDto> reschedule(
      String id, DateTime newStartsAt) async {
    final response = await _dio.patch<Map<String, dynamic>>(
      '/cabinet/appointments/$id',
      data: {'starts_at': newStartsAt.toIso8601String()},
    );
    return CabinetAppointmentDto.fromJson(response.data!);
  }

  /// `POST /v1/cabinet/appointments/series` (#4088) — contrat back
  /// (`CreateAppointmentSeriesBody`) : { practitioner_id, patient_id,
  /// motif?, occurrences: [{ starts_at, ends_at }] }.
  Future<AppointmentSeriesDto> createSeries({
    required String practitionerId,
    required String patientId,
    String? motif,
    required List<AppointmentSeriesOccurrence> occurrences,
  }) async {
    final data = <String, dynamic>{
      'practitioner_id': practitionerId,
      'patient_id': patientId,
      if (motif != null && motif.trim().isNotEmpty) 'motif': motif,
      'occurrences': occurrences
          .map((o) => {
                'starts_at': o.startsAt.toIso8601String(),
                'ends_at': o.endsAt.toIso8601String(),
              })
          .toList(),
    };
    final response = await _dio.post<Map<String, dynamic>>(
      '/cabinet/appointments/series',
      data: data,
    );
    return AppointmentSeriesDto.fromJson(response.data!);
  }
}

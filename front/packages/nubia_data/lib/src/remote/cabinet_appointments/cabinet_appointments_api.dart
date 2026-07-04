import 'package:dio/dio.dart';
import 'package:nubia_core/src/network/api_client.dart';
import 'package:nubia_data/src/remote/cabinet_appointments/cabinet_appointments_dto.dart';
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
    final dto = CabinetAppointmentDto(
      id: '',
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
    final response = await _dio.post<Map<String, dynamic>>(
      '/cabinet/appointments',
      data: dto.toJson(),
    );
    return CabinetAppointmentDto.fromJson(response.data!);
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
      '/cabinet/appointments/$id/reschedule',
      data: {'starts_at': newStartsAt.toIso8601String()},
    );
    return CabinetAppointmentDto.fromJson(response.data!);
  }
}

import 'package:dio/dio.dart';
import 'package:nubia_core/src/network/api_client.dart';
import 'package:nubia_data/src/remote/consultation/consultation_dto.dart';
import 'package:nubia_domain/src/entities/consultation_context.dart';

class ConsultationApi {
  final Dio _dio;

  ConsultationApi(ApiClient client) : _dio = client.dio;

  Future<List<ConsultationContextDto>> list({int page = 1}) async {
    final response = await _dio.get<List<dynamic>>(
      '/cabinet/consultations',
      queryParameters: {'page': page},
    );
    return (response.data!)
        .map((e) =>
            ConsultationContextDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<ConsultationContextDto> getById(String id) async {
    final response =
        await _dio.get<Map<String, dynamic>>('/cabinet/consultations/$id');
    return ConsultationContextDto.fromJson(response.data!);
  }

  Future<ConsultationContextDto> create(
      ConsultationContext consultation) async {
    final dto = ConsultationContextDto(
      id: '',
      cabinetId: consultation.cabinetId,
      appointmentId: consultation.appointmentId,
      patientId: consultation.patientId,
      patientName: consultation.patientName,
      practitionerId: consultation.practitionerId,
      startedAt: consultation.startedAt.toIso8601String(),
      endedAt: consultation.endedAt?.toIso8601String(),
      notes: consultation.notes,
      isCompleted: consultation.isCompleted,
    );
    final response = await _dio.post<Map<String, dynamic>>(
      '/cabinet/consultations',
      data: dto.toJson(),
    );
    return ConsultationContextDto.fromJson(response.data!);
  }

  Future<ConsultationContextDto> update(
      ConsultationContext consultation) async {
    final dto = ConsultationContextDto(
      id: consultation.id,
      cabinetId: consultation.cabinetId,
      appointmentId: consultation.appointmentId,
      patientId: consultation.patientId,
      patientName: consultation.patientName,
      practitionerId: consultation.practitionerId,
      startedAt: consultation.startedAt.toIso8601String(),
      endedAt: consultation.endedAt?.toIso8601String(),
      notes: consultation.notes,
      isCompleted: consultation.isCompleted,
    );
    final response = await _dio.patch<Map<String, dynamic>>(
      '/cabinet/consultations/${consultation.id}',
      data: dto.toJson(),
    );
    return ConsultationContextDto.fromJson(response.data!);
  }
}

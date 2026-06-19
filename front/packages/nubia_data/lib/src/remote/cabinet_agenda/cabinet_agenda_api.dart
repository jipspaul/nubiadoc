import 'package:dio/dio.dart';
import 'package:nubia_core/src/network/api_client.dart';
import 'package:nubia_data/src/remote/cabinet_agenda/cabinet_agenda_dto.dart';
import 'package:nubia_domain/src/entities/agenda_entry.dart';

class CabinetAgendaApi {
  final Dio _dio;

  CabinetAgendaApi(ApiClient client) : _dio = client.dio;

  Future<List<AgendaEntryDto>> list({
    DateTime? from,
    DateTime? to,
    String? practitionerId,
  }) async {
    final response = await _dio.get<List<dynamic>>(
      '/cabinet/agenda',
      queryParameters: {
        if (from != null) 'from': from.toIso8601String(),
        if (to != null) 'to': to.toIso8601String(),
        if (practitionerId != null) 'practitioner_id': practitionerId,
      },
    );
    return (response.data!)
        .map((e) => AgendaEntryDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<AgendaEntryDto> getById(String id) async {
    final response =
        await _dio.get<Map<String, dynamic>>('/cabinet/agenda/$id');
    return AgendaEntryDto.fromJson(response.data!);
  }

  Future<AgendaEntryDto> create(AgendaEntry entry) async {
    final dto = AgendaEntryDto(
      id: '',
      cabinetId: entry.cabinetId,
      practitionerId: entry.practitionerId,
      practitionerName: entry.practitionerName,
      startsAt: entry.startsAt.toIso8601String(),
      endsAt: entry.endsAt.toIso8601String(),
      patientId: entry.patientId,
      patientName: entry.patientName,
      motif: entry.motif,
      isFree: entry.isFree,
    );
    final response = await _dio.post<Map<String, dynamic>>(
      '/cabinet/agenda',
      data: dto.toJson(),
    );
    return AgendaEntryDto.fromJson(response.data!);
  }

  Future<AgendaEntryDto> update(AgendaEntry entry) async {
    final dto = AgendaEntryDto(
      id: entry.id,
      cabinetId: entry.cabinetId,
      practitionerId: entry.practitionerId,
      practitionerName: entry.practitionerName,
      startsAt: entry.startsAt.toIso8601String(),
      endsAt: entry.endsAt.toIso8601String(),
      patientId: entry.patientId,
      patientName: entry.patientName,
      motif: entry.motif,
      isFree: entry.isFree,
    );
    final response = await _dio.patch<Map<String, dynamic>>(
      '/cabinet/agenda/${entry.id}',
      data: dto.toJson(),
    );
    return AgendaEntryDto.fromJson(response.data!);
  }
}

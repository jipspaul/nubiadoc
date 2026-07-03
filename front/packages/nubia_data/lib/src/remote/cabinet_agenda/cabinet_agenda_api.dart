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
    // Le back renvoie un objet { practitioners: [...], slots: [...] } (séparés
    // pour le cloisonnement R.4127-72), pas un tableau plat. On fusionne ici :
    // chaque slot est enrichi du nom de son praticien.
    final response = await _dio.get<Map<String, dynamic>>(
      '/cabinet/agenda',
      queryParameters: {
        // L'API attend `date=YYYY-MM-DD` (+ `view`), pas `from`/`to`.
        if (from != null) 'date': _dateOnly(from),
        if (from != null && to != null)
          'view': to.difference(from).inDays > 1 ? 'week' : 'day',
        if (practitionerId != null) 'practitioner_id': practitionerId,
      },
    );
    final data = response.data ?? const <String, dynamic>{};

    final names = <String, String>{
      for (final p in (data['practitioners'] as List<dynamic>? ?? const []))
        (p as Map<String, dynamic>)['id'] as String:
            (p['display_name'] as String?) ?? '',
    };

    return (data['slots'] as List<dynamic>? ?? const [])
        .map((e) => AgendaEntryDto.fromSlotJson(
              e as Map<String, dynamic>,
              practitionerNames: names,
            ))
        .toList();
  }

  static String _dateOnly(DateTime dt) {
    final d = dt.toUtc();
    return '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
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

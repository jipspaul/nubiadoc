import 'package:dio/dio.dart';
import 'package:nubia_core/src/network/api_client.dart';
import 'package:nubia_data/src/remote/cabinet_agenda/cabinet_agenda_dto.dart';
import 'package:nubia_domain/src/entities/agenda_entry.dart';
import 'package:nubia_domain/src/entities/cabinet_practitioner.dart';

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
        .map(
          (e) => AgendaEntryDto.fromSlotJson(
            e as Map<String, dynamic>,
            practitionerNames: names,
          ),
        )
        .toList();
  }

  /// Roster des praticiens du cabinet — champ `practitioners` de
  /// GET /v1/cabinet/agenda (indépendant des RDV du jour). `cabinet_id` scopé
  /// côté serveur via le JWT.
  Future<List<CabinetPractitioner>> listPractitioners() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/cabinet/agenda',
      queryParameters: {'date': _dateOnly(DateTime.now()), 'view': 'week'},
    );
    final data = response.data ?? const <String, dynamic>{};
    return (data['practitioners'] as List<dynamic>? ?? const [])
        .map((p) => p as Map<String, dynamic>)
        .map(
          (p) => CabinetPractitioner(
            id: p['id'] as String,
            displayName: (p['display_name'] as String?) ?? '',
            specialite: p['specialite'] as String?,
          ),
        )
        .toList();
  }

  // `dt` représente déjà le jour calendaire voulu (souvent minuit local) :
  // on prend directement ses composantes year/month/day, sans passer par
  // `.toUtc()` qui ferait glisser la date d'un jour dès que l'heure locale
  // est en avance sur UTC (Europe/Paris été = UTC+2).
  static String _dateOnly(DateTime dt) {
    return '${dt.year.toString().padLeft(4, '0')}-'
        '${dt.month.toString().padLeft(2, '0')}-'
        '${dt.day.toString().padLeft(2, '0')}';
  }

  Future<AgendaEntryDto> getById(String id) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/cabinet/agenda/$id',
    );
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

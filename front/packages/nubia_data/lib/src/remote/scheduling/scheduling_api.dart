import 'package:dio/dio.dart';
import 'package:nubia_core/src/network/api_client.dart';
import 'package:nubia_data/src/remote/scheduling/appointment_dto.dart';

class DirectionsDto {
  final String deeplink;
  final int? durationMinutes;
  final double? distanceKm;

  const DirectionsDto({
    required this.deeplink,
    this.durationMinutes,
    this.distanceKm,
  });

  factory DirectionsDto.fromJson(Map<String, dynamic> json) => DirectionsDto(
        deeplink: json['deeplink'] as String,
        durationMinutes: json['duration_minutes'] as int?,
        distanceKm: (json['distance_km'] as num?)?.toDouble(),
      );
}

class PreparationItemDto {
  final String label;
  final bool required;

  const PreparationItemDto({required this.label, required this.required});

  factory PreparationItemDto.fromJson(Map<String, dynamic> json) =>
      PreparationItemDto(
        label: json['label'] as String,
        required: json['required'] as bool? ?? false,
      );
}

class PreparationAccessDto {
  final String? doorCode;
  final bool parking;
  final bool pmr;

  const PreparationAccessDto({
    this.doorCode,
    required this.parking,
    required this.pmr,
  });

  factory PreparationAccessDto.fromJson(Map<String, dynamic> json) =>
      PreparationAccessDto(
        doorCode: json['door_code'] as String?,
        parking: json['parking'] as bool? ?? false,
        pmr: json['pmr'] as bool? ?? false,
      );
}

class PreparationDto {
  final String? address;
  final String? providerName;
  final PreparationAccessDto? access;
  final DateTime? reminderAt;
  final List<PreparationItemDto> items;

  const PreparationDto({
    this.address,
    this.providerName,
    this.access,
    this.reminderAt,
    required this.items,
  });

  factory PreparationDto.fromJson(Map<String, dynamic> json) {
    final establishment = json['establishment'] as Map<String, dynamic>?;
    final provider = json['provider'] as Map<String, dynamic>?;
    final access = establishment?['access'] as Map<String, dynamic>?;
    final bring = json['bring'] as List<dynamic>? ?? const [];
    final reminderAt = json['reminder_at'] as String?;
    return PreparationDto(
      address: establishment?['address'] as String?,
      providerName: provider?['name'] as String?,
      access: access != null ? PreparationAccessDto.fromJson(access) : null,
      reminderAt: reminderAt != null ? DateTime.tryParse(reminderAt) : null,
      items: bring
          .map((e) => PreparationItemDto.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class SchedulingApi {
  final Dio _dio;

  SchedulingApi(ApiClient client) : _dio = client.dio;

  Future<List<AppointmentDto>> getUpcoming() async {
    final response = await _dio.get<Map<String, dynamic>>('/appointments',
        queryParameters: {'filter': 'upcoming'});
    final data = response.data!['data'] as List<dynamic>;
    return data
        .map((e) => AppointmentDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // `page` n'a pas d'existence côté API (pagination par cursor, cf.
  // api/src/appointments.rs `AppointmentsQuery`) : conservé uniquement pour
  // compatibilité de signature, sans effet. On suit `page.next_cursor` en
  // interne jusqu'à épuisement pour ramener l'historique complet.
  Future<List<AppointmentDto>> getHistory({int page = 1}) async {
    final result = <AppointmentDto>[];
    String? cursor;
    do {
      final response = await _dio.get<Map<String, dynamic>>(
        '/appointments',
        queryParameters: {
          'filter': 'history',
          if (cursor != null) 'cursor': cursor,
        },
      );
      final data = response.data!['data'] as List<dynamic>;
      result.addAll(
        data.map((e) => AppointmentDto.fromJson(e as Map<String, dynamic>)),
      );
      cursor = (response.data!['page'] as Map<String, dynamic>?)?['next_cursor']
          as String?;
    } while (cursor != null);
    return result;
  }

  Future<AppointmentDto> getById(String id) async {
    final response = await _dio.get<Map<String, dynamic>>('/appointments/$id');
    return AppointmentDto.fromJson(response.data!);
  }

  Future<AppointmentDto> book({
    required String slotId,
    required String motif,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/appointments',
      data: {'slot_id': slotId, 'motif': motif},
    );
    return AppointmentDto.fromJson(response.data!);
  }

  // #4543 : POST /appointments/:id/cancel répond `{appointment_id, status}`
  // (api/src/appointments.rs::CancelResponse), pas un appointment complet —
  // décoder cette réponse en AppointmentDto échouait systématiquement
  // (`starts_at` absent) et masquait une annulation pourtant réussie côté
  // serveur derrière une "erreur de décodage". On re-fetch l'appointment à
  // jour plutôt que de fabriquer un objet à partir d'un payload incomplet.
  Future<AppointmentDto> cancel(String id) async {
    await _dio.post<void>('/appointments/$id/cancel');
    return getById(id);
  }

  Future<AppointmentDto> modify({
    required String id,
    required DateTime newStartsAt,
  }) async {
    final response = await _dio.patch<Map<String, dynamic>>(
      '/appointments/$id',
      data: {'starts_at': newStartsAt.toIso8601String()},
    );
    return AppointmentDto.fromJson(response.data!);
  }

  // Même défaut de forme que cancel() (#4543) : POST .../checkin répond
  // `{appointment_id, status, checkin_at}` (api/src/appointments.rs::
  // CheckinResponse), pas un appointment complet.
  Future<AppointmentDto> checkin(String id) async {
    await _dio.post<void>('/appointments/$id/checkin');
    return getById(id);
  }

  Future<DirectionsDto> getDirections(String id, {String mode = 'car'}) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/appointments/$id/directions',
      queryParameters: {'mode': mode},
    );
    return DirectionsDto.fromJson(response.data!);
  }

  Future<PreparationDto> getPreparation(String id) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/appointments/$id/preparation',
    );
    return PreparationDto.fromJson(response.data!);
  }
}

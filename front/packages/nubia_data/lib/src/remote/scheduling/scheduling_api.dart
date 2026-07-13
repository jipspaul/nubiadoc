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

class PreparationDto {
  final String? address;
  final List<PreparationItemDto> items;

  const PreparationDto({this.address, required this.items});

  factory PreparationDto.fromJson(Map<String, dynamic> json) {
    final establishment = json['establishment'] as Map<String, dynamic>?;
    final bring = json['bring'] as List<dynamic>? ?? const [];
    return PreparationDto(
      address: establishment?['address'] as String?,
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

  Future<AppointmentDto> cancel(String id) async {
    final response =
        await _dio.post<Map<String, dynamic>>('/appointments/$id/cancel');
    return AppointmentDto.fromJson(response.data!);
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

  Future<AppointmentDto> checkin(String id) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/appointments/$id/checkin',
    );
    return AppointmentDto.fromJson(response.data!);
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

import 'package:dio/dio.dart';
import 'package:nubia_core/src/network/api_client.dart';
import 'package:nubia_data/src/remote/search/search_dto.dart';
import 'package:nubia_domain/src/entities/slot.dart';

class SlotsApi {
  final Dio _dio;

  SlotsApi(ApiClient client) : _dio = client.dio;

  Future<List<SlotDto>> list({
    DateTime? from,
    DateTime? to,
    String? practitionerId,
  }) async {
    final response = await _dio.get<List<dynamic>>(
      '/cabinet/slots',
      queryParameters: {
        if (from != null) 'from': from.toIso8601String(),
        if (to != null) 'to': to.toIso8601String(),
        if (practitionerId != null) 'practitioner_id': practitionerId,
      },
    );
    return (response.data!)
        .map((e) => SlotDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<SlotDto> getById(String id) async {
    final response = await _dio.get<Map<String, dynamic>>('/cabinet/slots/$id');
    return SlotDto.fromJson(response.data!);
  }

  Future<SlotDto> create(Slot slot) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/cabinet/slots',
      data: {
        'practitioner_id': slot.practitionerId,
        'starts_at': slot.startsAt.toIso8601String(),
        'ends_at': slot.endsAt.toIso8601String(),
        'is_available': slot.isAvailable,
      },
    );
    return SlotDto.fromJson(response.data!);
  }

  Future<SlotDto> update(Slot slot) async {
    final response = await _dio.patch<Map<String, dynamic>>(
      '/cabinet/slots/${slot.id}',
      data: {
        'practitioner_id': slot.practitionerId,
        'starts_at': slot.startsAt.toIso8601String(),
        'ends_at': slot.endsAt.toIso8601String(),
        'is_available': slot.isAvailable,
      },
    );
    return SlotDto.fromJson(response.data!);
  }
}

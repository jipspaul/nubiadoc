import 'package:dio/dio.dart';
import 'package:nubia_core/src/network/api_client.dart';
import 'package:nubia_data/src/remote/waiting_room/waiting_room_dto.dart';
import 'package:nubia_domain/src/entities/waiting_room_entry.dart';
import 'package:nubia_domain/src/entities/waiting_list_entry.dart';

class WaitingRoomApi {
  final Dio _dio;

  WaitingRoomApi(ApiClient client) : _dio = client.dio;

  // --- Salle d'attente (waiting room) ---

  Future<List<WaitingRoomEntryDto>> listWaitingRoom() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/cabinet/waiting-room',
    );
    final data = (response.data!['data'] as List<dynamic>?) ?? [];
    return data
        .map((e) => WaitingRoomEntryDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<WaitingRoomEntryDto> getWaitingRoomById(String id) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/cabinet/waiting-room/$id',
    );
    return WaitingRoomEntryDto.fromJson(response.data!);
  }

  Future<WaitingRoomEntryDto> createWaitingRoomEntry(
    WaitingRoomEntry entry,
  ) async {
    final dto = WaitingRoomEntryDto(
      id: '',
      cabinetId: entry.cabinetId,
      patientId: entry.patientId,
      patientName: entry.patientName,
      appointmentId: entry.appointmentId,
      arrivedAt: entry.arrivedAt.toIso8601String(),
      estimatedWaitMinutes: entry.estimatedWaitMinutes,
    );
    final response = await _dio.post<Map<String, dynamic>>(
      '/cabinet/waiting-room',
      data: dto.toJson(),
    );
    return WaitingRoomEntryDto.fromJson(response.data!);
  }

  Future<WaitingRoomEntryDto> callNext() async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/cabinet/waiting-room/call-next',
    );
    return WaitingRoomEntryDto.fromJson(response.data!);
  }

  Future<WaitingRoomEntryDto> updateWaitingRoomEntry(
    WaitingRoomEntry entry,
  ) async {
    final dto = WaitingRoomEntryDto(
      id: entry.id,
      cabinetId: entry.cabinetId,
      patientId: entry.patientId,
      patientName: entry.patientName,
      appointmentId: entry.appointmentId,
      arrivedAt: entry.arrivedAt.toIso8601String(),
      estimatedWaitMinutes: entry.estimatedWaitMinutes,
    );
    final response = await _dio.patch<Map<String, dynamic>>(
      '/cabinet/waiting-room/${entry.id}',
      data: dto.toJson(),
    );
    return WaitingRoomEntryDto.fromJson(response.data!);
  }

  // --- Liste d'attente (waiting list) ---

  Future<List<WaitingListEntryDto>> listWaitingList() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/cabinet/waiting-list',
    );
    final data = (response.data!['data'] as List<dynamic>?) ?? [];
    return data
        .map((e) => WaitingListEntryDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<WaitingListEntryDto> getWaitingListById(String id) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/cabinet/waiting-list/$id',
    );
    return WaitingListEntryDto.fromJson(response.data!);
  }

  Future<WaitingListEntryDto> createWaitingListEntry(
    WaitingListEntry entry,
  ) async {
    final dto = WaitingListEntryDto(
      id: '',
      cabinetId: entry.cabinetId,
      patientId: entry.patientId,
      patientName: entry.patientName,
      motif: entry.motif,
      requestedAt: entry.requestedAt.toIso8601String(),
      position: entry.position,
    );
    final response = await _dio.post<Map<String, dynamic>>(
      '/cabinet/waiting-list',
      data: dto.toJson(),
    );
    return WaitingListEntryDto.fromJson(response.data!);
  }

  Future<WaitingListEntryDto> updateWaitingListEntry(
    WaitingListEntry entry,
  ) async {
    final dto = WaitingListEntryDto(
      id: entry.id,
      cabinetId: entry.cabinetId,
      patientId: entry.patientId,
      patientName: entry.patientName,
      motif: entry.motif,
      requestedAt: entry.requestedAt.toIso8601String(),
      position: entry.position,
    );
    final response = await _dio.patch<Map<String, dynamic>>(
      '/cabinet/waiting-list/${entry.id}',
      data: dto.toJson(),
    );
    return WaitingListEntryDto.fromJson(response.data!);
  }

  Future<void> offerSlot(String id) async {
    // #4536 : `proposed_at` est désormais optionnel côté back — l'écran
    // « Combler » ne sélectionne pas de créneau précis, et le front n'a de
    // toute façon aucun moyen de connaître les créneaux RÉELS du provider de
    // l'entrée (non exposés par GET /cabinet/waiting-list). Avant ce fix, un
    // horodatage fabriqué `now()+15min` était envoyé, qui ne correspondait
    // quasi jamais à un vrai `availability_slot` → 409 systématique malgré
    // des créneaux disponibles ailleurs. Le back choisit maintenant lui-même
    // le prochain créneau ouvert du provider (`offer_waiting_list_slot`).
    await _dio.post<void>('/cabinet/waiting-list/$id/offer', data: const {});
  }
}

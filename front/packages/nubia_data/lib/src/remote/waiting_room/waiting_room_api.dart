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
    // Le back exige un corps JSON `{ proposed_at }` (ISO 8601 UTC) — cf.
    // `OfferSlotBody` côté Rust. Sans corps → 415/400. L'écran « Combler » ne
    // sélectionne pas de créneau précis : on propose le prochain créneau
    // disponible, le back se contente de marquer l'entrée `fulfilled` et de
    // notifier le patient. Le back rejette (422) tout `proposed_at` <=
    // now+5min (cf. `offer_waiting_list_slot`) : on marge donc largement
    // au-delà de ce seuil pour éviter tout écart de latence réseau/horloge.
    await _dio.post<void>(
      '/cabinet/waiting-list/$id/offer',
      data: {
        'proposed_at': DateTime.now()
            .toUtc()
            .add(const Duration(minutes: 15))
            .toIso8601String(),
      },
    );
  }
}

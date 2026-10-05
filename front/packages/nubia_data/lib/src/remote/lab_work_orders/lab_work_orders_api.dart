import 'package:dio/dio.dart';
import 'package:nubia_core/src/network/api_client.dart';
import 'package:nubia_data/src/remote/lab_work_orders/lab_price_list_item_dto.dart';
import 'package:nubia_data/src/remote/lab_work_orders/lab_work_order_dto.dart';
import 'package:nubia_data/src/remote/lab_work_orders/today_lab_work_order_dto.dart';

class LabWorkOrdersApi {
  final Dio _dio;

  LabWorkOrdersApi(ApiClient client) : _dio = client.dio;

  /// GET /cabinet/lab-work-orders (#4149).
  Future<List<LabWorkOrderDto>> listOrders() async {
    final response = await _dio.get<List<dynamic>>('/cabinet/lab-work-orders');
    return (response.data ?? [])
        .map((e) => LabWorkOrderDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// GET /cabinet/lab-work-orders/today (#7208) : bons dont le RDV de pose
  /// tombe aujourd'hui ou demain.
  Future<List<TodayLabWorkOrderDto>> today() async {
    final response =
        await _dio.get<List<dynamic>>('/cabinet/lab-work-orders/today');
    return (response.data ?? [])
        .map((e) => TodayLabWorkOrderDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// POST /cabinet/lab-work-orders (#8031). Ne renvoie que l'id créé (statut
  /// `sent` par défaut côté API) — l'appelant recharge la liste pour
  /// l'afficher avec `patient_display_name`/`sent_at` résolus serveur.
  Future<String> createOrder({
    required String patientId,
    required String labName,
    required int purchasePriceCents,
    String? expectedReturnAt,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/cabinet/lab-work-orders',
      data: {
        'patient_id': patientId,
        'lab_name': labName,
        'purchase_price_cents': purchasePriceCents,
        if (expectedReturnAt != null) 'expected_return_at': expectedReturnAt,
      },
    );
    return response.data!['order_id'] as String;
  }

  /// PATCH /cabinet/lab-work-orders/:id (#4149). Renvoie le nouveau statut.
  Future<String> updateStatus(String orderId, String status) async {
    final response = await _dio.patch<Map<String, dynamic>>(
      '/cabinet/lab-work-orders/$orderId',
      data: {'status': status},
    );
    return response.data!['status'] as String;
  }

  /// GET /cabinet/lab-price-list (#7163, DP-F19.c) : grille tarifaire du
  /// cabinet, pour la sélection d'un produit à la commande (prix pré-rempli).
  Future<List<LabPriceListItemDto>> listPriceList() async {
    final response =
        await _dio.get<List<dynamic>>('/cabinet/lab-price-list');
    return (response.data ?? [])
        .map((e) => LabPriceListItemDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}

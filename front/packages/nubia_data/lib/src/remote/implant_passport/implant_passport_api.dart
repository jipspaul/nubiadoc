import 'package:dio/dio.dart';
import 'package:nubia_core/src/network/api_client.dart';
import 'package:nubia_data/src/remote/implant_passport/implant_passport_dto.dart';

class ImplantPassportApi {
  final Dio _dio;

  ImplantPassportApi(ApiClient client) : _dio = client.dio;

  /// GET /implant-passport (#4142).
  Future<List<ImplantItemDto>> listPassport() async {
    final response = await _dio.get<Map<String, dynamic>>('/implant-passport');
    final data = (response.data?['data'] as List<dynamic>?) ?? [];
    return data
        .map((e) => ImplantItemDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// GET /implant-passport/export (#4142). Toujours une redirection 302 —
  /// on ne la suit pas et on lit l'URL signée dans `Location`.
  Future<String> exportPassport() async {
    final response = await _dio.get<void>(
      '/implant-passport/export',
      options: Options(followRedirects: false, validateStatus: (s) => s == 302),
    );
    return response.headers.value('location') ?? '';
  }

  /// POST /cabinet/patients/{id}/implants (#4140) — écriture côté praticien.
  /// Ne renvoie que l'id créé (pas les champs) : le repository reconstruit
  /// l'entité affichable à partir des valeurs du formulaire déjà connues.
  Future<String> createImplant({
    required String patientId,
    required String brand,
    required String implantRef,
    String? lotNumber,
    String? placementDate,
    String? toothPosition,
    String? notes,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/cabinet/patients/$patientId/implants',
      data: {
        'brand': brand,
        'implant_ref': implantRef,
        if (lotNumber != null) 'lot_number': lotNumber,
        if (placementDate != null) 'placement_date': placementDate,
        if (toothPosition != null) 'tooth_position': toothPosition,
        if (notes != null) 'notes': notes,
      },
    );
    return response.data!['implant_id'] as String;
  }
}

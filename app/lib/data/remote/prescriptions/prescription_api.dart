import 'package:dio/dio.dart';
import 'package:injectable/injectable.dart';
import 'package:nubia_patient/core/network/api_client.dart';
import 'package:nubia_patient/data/remote/prescriptions/prescription_dto.dart';
import 'package:nubia_patient/domain/entities/prescription.dart';

@injectable
class PrescriptionApi {
  final Dio _dio;

  PrescriptionApi(ApiClient client) : _dio = client.dio;

  /// POST /v1/cabinet/prescriptions
  Future<PrescriptionDto> createPrescription({
    required String patientId,
    required List<PrescriptionItem> items,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/cabinet/prescriptions',
      data: {
        'patient_id': patientId,
        'items': items
            .map((i) => PrescriptionItemDto.fromDomain(i).toJson())
            .toList(),
      },
    );
    return PrescriptionDto.fromJson(response.data!);
  }

  /// POST /v1/cabinet/prescriptions/{id}/sign
  Future<PrescriptionDto> signPrescription(String id) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/cabinet/prescriptions/$id/sign',
    );
    return PrescriptionDto.fromJson(response.data!);
  }
}

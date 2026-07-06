import 'package:dio/dio.dart';
import 'package:nubia_core/src/network/api_client.dart';
import 'package:nubia_data/src/remote/cabinet_quotes/cabinet_quotes_dto.dart';
import 'package:nubia_domain/src/entities/cabinet_quote.dart';

class CabinetQuotesApi {
  final Dio _dio;

  CabinetQuotesApi(ApiClient client) : _dio = client.dio;

  Future<List<CabinetQuoteDto>> list({int page = 1}) async {
    // Le back renvoie un tableau nu `[CabinetQuoteItem]` (pas de wrapper
    // `{data}`). On tolère les deux formes par robustesse.
    final response = await _dio.get<dynamic>(
      '/cabinet/quotes',
      queryParameters: {'page': page},
    );
    final raw = response.data;
    final data = raw is List
        ? raw
        : ((raw as Map<String, dynamic>?)?['data'] as List<dynamic>? ??
            const []);
    return data
        .map((e) => CabinetQuoteDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<CabinetQuoteDto> getById(String id) async {
    final response =
        await _dio.get<Map<String, dynamic>>('/cabinet/quotes/$id');
    return CabinetQuoteDto.fromJson(response.data!);
  }

  Future<CabinetQuoteDto> create(CabinetQuote quote) async {
    final dto = CabinetQuoteDto(
      id: '',
      cabinetId: quote.cabinetId,
      patientId: quote.patientId,
      patientName: quote.patientName,
      totalCents: quote.totalCents,
      patientShareCents: quote.patientShareCents,
      status: quote.status.name,
      createdAt: quote.createdAt.toIso8601String(),
      signedAt: quote.signedAt?.toIso8601String(),
      expiresAt: quote.expiresAt?.toIso8601String(),
    );
    final response = await _dio.post<Map<String, dynamic>>(
      '/cabinet/quotes',
      data: dto.toJson(),
    );
    return CabinetQuoteDto.fromJson(response.data!);
  }

  /// POST /cabinet/quotes/:id/send — envoie le devis (brouillon) au patient.
  /// Le back renvoie `{ id, status, sent }` ; on retourne le statut confirmé.
  Future<CabinetQuoteStatus> send(String id) async {
    final response =
        await _dio.post<Map<String, dynamic>>('/cabinet/quotes/$id/send');
    final status = response.data?['status'] as String? ?? 'sent';
    return CabinetQuoteDto.parseStatus(status);
  }

  Future<CabinetQuoteDto> update(CabinetQuote quote) async {
    final dto = CabinetQuoteDto(
      id: quote.id,
      cabinetId: quote.cabinetId,
      patientId: quote.patientId,
      patientName: quote.patientName,
      totalCents: quote.totalCents,
      patientShareCents: quote.patientShareCents,
      status: quote.status.name,
      createdAt: quote.createdAt.toIso8601String(),
      signedAt: quote.signedAt?.toIso8601String(),
      expiresAt: quote.expiresAt?.toIso8601String(),
    );
    final response = await _dio.patch<Map<String, dynamic>>(
      '/cabinet/quotes/${quote.id}',
      data: dto.toJson(),
    );
    return CabinetQuoteDto.fromJson(response.data!);
  }
}

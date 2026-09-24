import 'package:dio/dio.dart';
import 'package:nubia_core/src/network/api_client.dart';
import 'package:nubia_data/src/remote/cabinet_quotes/cabinet_quotes_dto.dart';
import 'package:nubia_domain/src/entities/cabinet_quote.dart';

class CabinetQuotesApi {
  final Dio _dio;

  /// Taille de page utilisée pour paginer le cabinet entier (max serveur,
  /// `cabinet_quotes.rs` `.clamp(1, 500)`) — voir `list`.
  static const _cabinetPageSize = 500;

  CabinetQuotesApi(ApiClient client) : _dio = client.dio;

  // Le back renvoie un tableau nu `[CabinetQuoteItem]` (pas de wrapper
  // `{data}`, ni de curseur) et applique un défaut de 200 lignes sans le
  // signaler (#7553 : la liste cabinet entier était figée aux 200 premiers
  // devis). L'endpoint ne supporte pas la pagination `page` (rejet 400
  // `unsupported_pagination_param`) ; `page` n'est donc pas transmis.
  // `patient_id`/`limit`/`offset` sont eux supportés (#4419/#4519/#3521).
  //
  // Quand l'appelant fixe déjà `limit`/`offset` (pagination manuelle, ex.
  // `ListPatientJournalUseCase._listAllCabinetQuotes` qui pagine par
  // patient), on ne fait qu'une seule requête. Sinon (cabinet entier, sans
  // `patient_id` précis de page), on pagine nous-mêmes par `offset` tant
  // qu'une page pleine est renvoyée, pour ne jamais tronquer silencieusement
  // à la limite par défaut du serveur.
  Future<List<CabinetQuoteDto>> list({
    int page = 1,
    String? patientId,
    int? limit,
    int? offset,
  }) async {
    if (limit != null || offset != null) {
      return _fetchPage(patientId: patientId, limit: limit, offset: offset);
    }
    final result = <CabinetQuoteDto>[];
    var currentOffset = 0;
    while (true) {
      final pageItems = await _fetchPage(
        patientId: patientId,
        limit: _cabinetPageSize,
        offset: currentOffset,
      );
      result.addAll(pageItems);
      if (pageItems.length < _cabinetPageSize) break;
      currentOffset += _cabinetPageSize;
    }
    return result;
  }

  Future<List<CabinetQuoteDto>> _fetchPage({
    String? patientId,
    int? limit,
    int? offset,
  }) async {
    final response = await _dio.get<dynamic>(
      '/cabinet/quotes',
      queryParameters: {
        if (patientId != null) 'patient_id': patientId,
        if (limit != null) 'limit': limit,
        if (offset != null) 'offset': offset,
      },
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
      quoteRef: '',
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
      quoteRef: quote.quoteRef,
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

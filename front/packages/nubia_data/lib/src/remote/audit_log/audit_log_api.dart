import 'package:dio/dio.dart';
import 'package:nubia_core/src/network/api_client.dart';
import 'package:nubia_data/src/remote/audit_log/audit_log_entry_dto.dart';

class AuditLogApi {
  final Dio _dio;

  AuditLogApi(ApiClient client) : _dio = client.dio;

  /// GET /cabinet/audit-log (#4155). Réponse `{ data: [...] }`. `from`/`to`
  /// en `YYYY-MM-DD` (le back attend un jour entier, pas un timestamp).
  Future<List<AuditLogEntryDto>> getAuditLog({
    DateTime? from,
    DateTime? to,
    String? entity,
  }) async {
    final query = <String, dynamic>{
      if (from != null) 'from': _isoDate(from),
      if (to != null) 'to': _isoDate(to),
      if (entity != null) 'entity': entity,
    };
    final response = await _dio.get<Map<String, dynamic>>(
      '/cabinet/audit-log',
      queryParameters: query,
    );
    final data = (response.data?['data'] as List<dynamic>?) ?? [];
    return data
        .map((e) => AuditLogEntryDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static String _isoDate(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

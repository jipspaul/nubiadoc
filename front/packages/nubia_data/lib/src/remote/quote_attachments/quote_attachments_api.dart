import 'package:dio/dio.dart';
import 'package:nubia_core/src/network/api_client.dart';
import 'package:nubia_data/src/remote/quote_attachments/quote_attachment_dto.dart';

class QuoteAttachmentsApi {
  final Dio _dio;

  QuoteAttachmentsApi(ApiClient client) : _dio = client.dio;

  Future<List<QuoteAttachmentDto>> list(String quoteId) async {
    final response = await _dio
        .get<Map<String, dynamic>>('/cabinet/quotes/$quoteId/attachments');
    final data = response.data?['data'] as List<dynamic>? ?? const [];
    return data
        .map((e) => QuoteAttachmentDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<QuoteAttachmentDto> create(
    String quoteId, {
    required String kind,
    String? documentId,
    String? templateRef,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/cabinet/quotes/$quoteId/attachments',
      data: {
        'kind': kind,
        if (documentId != null) 'document_id': documentId,
        if (templateRef != null) 'template_ref': templateRef,
      },
    );
    return QuoteAttachmentDto.fromJson(response.data!);
  }

  Future<void> delete(String quoteId, String attachmentId) async {
    await _dio.delete<void>(
      '/cabinet/quotes/$quoteId/attachments/$attachmentId',
    );
  }
}

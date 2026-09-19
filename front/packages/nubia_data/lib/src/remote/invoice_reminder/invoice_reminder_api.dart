import 'package:dio/dio.dart';
import 'package:nubia_core/src/network/api_client.dart';
import 'package:nubia_data/src/remote/invoice_reminder/invoice_reminder_dto.dart';

class InvoiceReminderApi {
  final Dio _dio;

  InvoiceReminderApi(ApiClient client) : _dio = client.dio;

  Future<void> send(String invoiceId) async {
    await _dio.post<Map<String, dynamic>>('/invoices/$invoiceId/reminder');
  }

  Future<List<InvoiceReminderDto>> listHistory(String invoiceId) async {
    final response = await _dio
        .get<Map<String, dynamic>>('/invoices/$invoiceId/reminders');
    final data = response.data?['data'] as List<dynamic>? ?? const [];
    return data
        .map((e) => InvoiceReminderDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}

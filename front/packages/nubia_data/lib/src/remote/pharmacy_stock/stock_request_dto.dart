import 'package:nubia_domain/src/entities/stock_request.dart';

class StockRequestDto {
  final String id;
  final String pharmacyId;
  final String? cabinetName;
  final List<Map<String, dynamic>> items;
  final String status;
  final String? responseNote;
  final String createdAt;

  const StockRequestDto({
    required this.id,
    required this.pharmacyId,
    this.cabinetName,
    required this.items,
    required this.status,
    this.responseNote,
    required this.createdAt,
  });

  factory StockRequestDto.fromJson(Map<String, dynamic> json) =>
      StockRequestDto(
        id: json['id'] as String,
        pharmacyId: json['pharmacy_id'] as String? ?? '',
        cabinetName: json['cabinet_name'] as String?,
        items: (json['items'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .toList(),
        status: json['status'] as String? ?? 'sent',
        responseNote: json['response_note'] as String?,
        createdAt: json['created_at'] as String? ??
            DateTime.fromMillisecondsSinceEpoch(0).toIso8601String(),
      );

  StockRequest toDomain() => StockRequest(
        id: id,
        pharmacyId: pharmacyId,
        cabinetName: cabinetName,
        items: items
            .map(
              (item) => StockRequestItem(
                label: item['label'] as String? ?? '',
                quantity: (item['qty'] ?? item['quantity']) as int? ?? 1,
                note: item['note'] as String?,
                availability: _parseAvailability(item['availability']),
              ),
            )
            .toList(),
        status: _parseStatus(status),
        responseNote: responseNote,
        createdAt: DateTime.parse(createdAt),
      );

  static StockItemAvailability? _parseAvailability(dynamic value) {
    switch (value) {
      case 'partial':
        return StockItemAvailability.partial;
      case 'full':
        return StockItemAvailability.full;
      default:
        return null;
    }
  }

  static StockRequestStatus _parseStatus(String value) {
    switch (value) {
      case 'accepted':
        return StockRequestStatus.accepted;
      case 'rejected':
        return StockRequestStatus.rejected;
      case 'fulfilled':
        return StockRequestStatus.fulfilled;
      case 'cancelled':
        return StockRequestStatus.cancelled;
      case 'sent':
      default:
        return StockRequestStatus.sent;
    }
  }
}

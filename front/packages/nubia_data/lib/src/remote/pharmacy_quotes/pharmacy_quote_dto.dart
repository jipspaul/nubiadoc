import 'package:nubia_domain/src/entities/pharmacy_quote.dart';

class PharmacyQuoteDto {
  final String id;
  final String pharmacyId;
  final String? pharmacyName;
  final String? patientDisplayName;
  final String? orderId;
  final List<Map<String, dynamic>> items;
  final int totalCents;
  final String status;
  final String createdAt;
  final String? sentAt;
  final String? decidedAt;

  const PharmacyQuoteDto({
    required this.id,
    required this.pharmacyId,
    this.pharmacyName,
    this.patientDisplayName,
    this.orderId,
    required this.items,
    required this.totalCents,
    required this.status,
    required this.createdAt,
    this.sentAt,
    this.decidedAt,
  });

  factory PharmacyQuoteDto.fromJson(Map<String, dynamic> json) =>
      PharmacyQuoteDto(
        id: json['id'] as String,
        pharmacyId: json['pharmacy_id'] as String? ?? '',
        pharmacyName: json['pharmacy_name'] as String?,
        patientDisplayName: json['patient_display_name'] as String?,
        orderId: json['order_id'] as String?,
        items: (json['items'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .toList(),
        totalCents:
            ((json['total_cents'] ?? json['total_amount_cents']) as num? ?? 0)
                .toInt(),
        status: json['status'] as String? ?? 'draft',
        createdAt: json['created_at'] as String? ??
            DateTime.fromMillisecondsSinceEpoch(0).toIso8601String(),
        sentAt: json['sent_at'] as String?,
        decidedAt: json['decided_at'] as String?,
      );

  PharmacyQuote toDomain() => PharmacyQuote(
        id: id,
        pharmacyId: pharmacyId,
        pharmacyName: pharmacyName,
        patientDisplayName: patientDisplayName,
        orderId: orderId,
        items: items
            .map(
              (item) => PharmacyQuoteItem(
                label: item['label'] as String? ?? '',
                quantity: (item['qty'] ?? item['quantity']) as int? ?? 1,
                unitPriceCents: (item['unit_price_cents'] as num? ?? 0).toInt(),
              ),
            )
            .toList(),
        totalCents: totalCents,
        status: _parseStatus(status),
        createdAt: DateTime.parse(createdAt),
        sentAt: sentAt != null ? DateTime.parse(sentAt!) : null,
        decidedAt: decidedAt != null ? DateTime.parse(decidedAt!) : null,
      );

  static PharmacyQuoteStatus _parseStatus(String value) {
    switch (value) {
      case 'sent':
        return PharmacyQuoteStatus.sent;
      case 'accepted':
        return PharmacyQuoteStatus.accepted;
      case 'refused':
        return PharmacyQuoteStatus.refused;
      case 'expired':
        return PharmacyQuoteStatus.expired;
      case 'draft':
      default:
        return PharmacyQuoteStatus.draft;
    }
  }
}

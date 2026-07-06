import 'package:nubia_domain/src/entities/cabinet_quote.dart';
import 'package:nubia_domain/src/entities/quote.dart';

class CabinetQuoteDto {
  final String id;
  final String cabinetId;
  final String patientId;
  final String patientName;
  final int totalCents;
  final int patientShareCents;
  final String status;
  final String createdAt;
  final String? signedAt;
  final String? expiresAt;

  /// Lignes du devis — présentes uniquement sur le détail
  /// (`GET /v1/cabinet/quotes/:id`), absentes de la liste.
  final List<QuoteLineItem>? items;

  const CabinetQuoteDto({
    required this.id,
    required this.cabinetId,
    required this.patientId,
    required this.patientName,
    required this.totalCents,
    required this.patientShareCents,
    required this.status,
    required this.createdAt,
    this.signedAt,
    this.expiresAt,
    this.items,
  });

  factory CabinetQuoteDto.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'] as List<dynamic>?;
    return CabinetQuoteDto(
      id: json['id'] as String,
      cabinetId: json['cabinet_id'] as String? ?? '',
      // patient_id / patient_name sont Option côté back (LEFT JOIN patient).
      patientId: json['patient_id'] as String? ?? '',
      patientName: json['patient_name'] as String? ?? 'Patient inconnu',
      totalCents:
          ((json['total_amount'] ?? json['total_cents']) as num? ?? 0).toInt(),
      patientShareCents: (json['patient_share_cents'] as num? ?? 0).toInt(),
      status: json['status'] as String,
      createdAt: json['created_at'] as String,
      signedAt: json['signed_at'] as String?,
      expiresAt: json['expires_at'] as String?,
      items: rawItems
          ?.map((e) => _lineFromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  static QuoteLineItem _lineFromJson(Map<String, dynamic> json) =>
      QuoteLineItem(
        id: json['id'] as String? ?? '',
        label: json['label'] as String? ?? '',
        totalCents: ((json['total_amount'] ?? json['total_cents']) as num? ?? 0)
            .toInt(),
        amoShareCents: (json['amo_share_cents'] as num? ?? 0).toInt(),
        amcShareCents: (json['amc_share_cents'] as num? ?? 0).toInt(),
        patientShareCents: (json['patient_share_cents'] as num? ?? 0).toInt(),
      );

  Map<String, dynamic> toJson() => {
        'patient_id': patientId,
        'total_cents': totalCents,
        'patient_share_cents': patientShareCents,
        'status': status,
      };

  CabinetQuote toDomain() => CabinetQuote(
        id: id,
        cabinetId: cabinetId,
        patientId: patientId,
        patientName: patientName,
        totalCents: totalCents,
        patientShareCents: patientShareCents,
        status: parseStatus(status),
        createdAt: DateTime.parse(createdAt),
        signedAt: signedAt != null ? DateTime.parse(signedAt!) : null,
        expiresAt: expiresAt != null ? DateTime.parse(expiresAt!) : null,
        items: items,
      );

  static CabinetQuoteStatus parseStatus(String value) {
    switch (value) {
      case 'draft':
        return CabinetQuoteStatus.draft;
      case 'sent':
        return CabinetQuoteStatus.sent;
      case 'signed':
        return CabinetQuoteStatus.signed;
      case 'expired':
        return CabinetQuoteStatus.expired;
      case 'cancelled':
        return CabinetQuoteStatus.cancelled;
      default:
        return CabinetQuoteStatus.draft;
    }
  }
}

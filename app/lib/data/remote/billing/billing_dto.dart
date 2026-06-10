import 'package:nubia_patient/domain/entities/quote.dart';

class QuoteLineItemDto {
  final String id;
  final String label;
  final String? ccamCode;
  final String? toothLabel;
  final int totalCents;
  final int amoShareCents;
  final int amcShareCents;
  final int patientShareCents;

  const QuoteLineItemDto({
    required this.id,
    required this.label,
    this.ccamCode,
    this.toothLabel,
    required this.totalCents,
    required this.amoShareCents,
    required this.amcShareCents,
    required this.patientShareCents,
  });

  factory QuoteLineItemDto.fromJson(Map<String, dynamic> json) =>
      QuoteLineItemDto(
        id: json['id'] as String,
        label: json['label'] as String,
        ccamCode: json['ccam_code'] as String?,
        toothLabel: json['tooth_label'] as String?,
        totalCents: (json['total_cents'] as num).toInt(),
        amoShareCents: (json['amo_share_cents'] as num).toInt(),
        amcShareCents: (json['amc_share_cents'] as num).toInt(),
        patientShareCents: (json['patient_share_cents'] as num).toInt(),
      );

  QuoteLineItem toDomain() => QuoteLineItem(
        id: id,
        label: label,
        ccamCode: ccamCode,
        toothLabel: toothLabel,
        totalCents: totalCents,
        amoShareCents: amoShareCents,
        amcShareCents: amcShareCents,
        patientShareCents: patientShareCents,
      );
}

class QuoteDto {
  final String id;
  final String cabinetId;
  final String practitionerName;
  final List<QuoteLineItemDto> items;
  final int totalCents;
  final int patientShareCents;
  final int depositCents;
  final String status;
  final String createdAt;
  final String? signedAt;
  final String? expiresAt;
  final String? documentId;

  const QuoteDto({
    required this.id,
    required this.cabinetId,
    required this.practitionerName,
    required this.items,
    required this.totalCents,
    required this.patientShareCents,
    required this.depositCents,
    required this.status,
    required this.createdAt,
    this.signedAt,
    this.expiresAt,
    this.documentId,
  });

  factory QuoteDto.fromJson(Map<String, dynamic> json) => QuoteDto(
        id: json['id'] as String,
        cabinetId: json['cabinet_id'] as String,
        practitionerName: json['practitioner_name'] as String,
        items: (json['items'] as List<dynamic>? ?? [])
            .map((e) => QuoteLineItemDto.fromJson(e as Map<String, dynamic>))
            .toList(),
        totalCents: (json['total_cents'] as num).toInt(),
        patientShareCents: (json['patient_share_cents'] as num).toInt(),
        depositCents: (json['deposit_cents'] as num).toInt(),
        status: json['status'] as String,
        createdAt: json['created_at'] as String,
        signedAt: json['signed_at'] as String?,
        expiresAt: json['expires_at'] as String?,
        documentId: json['document_id'] as String?,
      );

  Quote toDomain() => Quote(
        id: id,
        cabinetId: cabinetId,
        practitionerName: practitionerName,
        items: items.map((i) => i.toDomain()).toList(),
        totalCents: totalCents,
        patientShareCents: patientShareCents,
        depositCents: depositCents,
        status: _parseStatus(status),
        createdAt: DateTime.parse(createdAt),
        signedAt: signedAt != null ? DateTime.parse(signedAt!) : null,
        expiresAt: expiresAt != null ? DateTime.parse(expiresAt!) : null,
        documentId: documentId,
      );

  static QuoteStatus _parseStatus(String raw) {
    switch (raw) {
      case 'draft':
        return QuoteStatus.draft;
      case 'sent':
        return QuoteStatus.sent;
      case 'signed':
        return QuoteStatus.signed;
      case 'expired':
        return QuoteStatus.expired;
      case 'cancelled':
        return QuoteStatus.cancelled;
      default:
        return QuoteStatus.draft;
    }
  }
}

class SignatureUrlDto {
  final String redirectUrl;

  const SignatureUrlDto({required this.redirectUrl});

  factory SignatureUrlDto.fromJson(Map<String, dynamic> json) =>
      SignatureUrlDto(redirectUrl: json['redirect_url'] as String);
}

class DepositSecretDto {
  final String clientSecret;

  const DepositSecretDto({required this.clientSecret});

  factory DepositSecretDto.fromJson(Map<String, dynamic> json) =>
      DepositSecretDto(clientSecret: json['client_secret'] as String);
}

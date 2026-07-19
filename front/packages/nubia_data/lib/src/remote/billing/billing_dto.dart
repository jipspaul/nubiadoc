import 'package:nubia_domain/src/entities/quote.dart';

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

  /// Contrat réel (api/src/billing.rs) : {id, label, ccam_code, tooth,
  /// unit_amount_cents, amo_part_cents?, amc_part_cents?}. Le reste à charge
  /// patient = montant - remboursements (0 si part inconnue).
  factory QuoteLineItemDto.fromJson(Map<String, dynamic> json) {
    final total =
        (json['unit_amount_cents'] ?? json['total_cents'] ?? 0 as num).toInt();
    final amo = (json['amo_part_cents'] as num?)?.toInt() ?? 0;
    final amc = (json['amc_part_cents'] as num?)?.toInt() ?? 0;
    return QuoteLineItemDto(
      id: json['id'] as String,
      label: json['label'] as String,
      ccamCode: json['ccam_code'] as String?,
      toothLabel: (json['tooth'] ?? json['tooth_label']) as String?,
      totalCents: total,
      amoShareCents: amo,
      amcShareCents: amc,
      patientShareCents: (total - amo - amc).clamp(0, total),
    );
  }

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

  /// Détail : GET /v1/quotes/:id → {id, status, total_amount_cents, currency,
  /// signed_at, created_at, items:[...]}. Champs absents de l'API
  /// (cabinet_id, practitioner_name, deposit) → valeurs neutres.
  factory QuoteDto.fromJson(Map<String, dynamic> json) {
    final items = (json['items'] as List<dynamic>? ?? [])
        .map((e) => QuoteLineItemDto.fromJson(e as Map<String, dynamic>))
        .toList();
    final total =
        (json['total_amount_cents'] ?? json['total_cents'] ?? 0 as num).toInt();
    final patientShare = items.isEmpty
        ? total
        : items.fold<int>(0, (s, i) => s + i.patientShareCents);
    return QuoteDto(
      id: json['id'] as String,
      cabinetId: (json['cabinet_id'] as String?) ?? '',
      practitionerName: (json['practitioner_name'] as String?) ?? '',
      items: items,
      totalCents: total,
      patientShareCents:
          (json['patient_share_cents'] as num?)?.toInt() ?? patientShare,
      depositCents: (json['deposit_cents'] as num?)?.toInt() ?? 0,
      status: json['status'] as String,
      createdAt: json['created_at'] as String,
      signedAt: json['signed_at'] as String?,
      expiresAt: json['expires_at'] as String?,
      documentId: json['document_id'] as String?,
    );
  }

  /// Liste : GET /v1/quotes → items résumés {id, status,
  /// total_amount_cents, currency, created_at} (sans lignes ni parts).
  factory QuoteDto.fromSummaryJson(Map<String, dynamic> json) {
    final total = (json['total_amount_cents'] as num?)?.toInt() ?? 0;
    return QuoteDto(
      id: json['id'] as String,
      cabinetId: '',
      practitionerName: '',
      items: const [],
      totalCents: total,
      patientShareCents: total,
      depositCents: 0,
      status: json['status'] as String,
      createdAt: json['created_at'] as String,
    );
  }

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

/// `POST /v1/quotes/:id/sign` signe le devis de façon SYNCHRONE côté API
/// (stub Yousign — cf. commentaire `sign_quote`, api/src/billing.rs) et
/// renvoie `{signed, signed_at}`, jamais `redirect_url` : il n'y a pas de
/// parcours de redirection à attendre. Avant : `json['redirect_url']` →
/// null → « Erreur de décodage de la réponse », alors que le devis était
/// déjà signé et verrouillé côté serveur (#3705).
class QuoteSignedDto {
  final bool signed;
  final String signedAt;

  const QuoteSignedDto({required this.signed, required this.signedAt});

  factory QuoteSignedDto.fromJson(Map<String, dynamic> json) => QuoteSignedDto(
        signed: json['signed'] as bool,
        signedAt: json['signed_at'] as String,
      );
}

class DepositSecretDto {
  final String clientSecret;

  const DepositSecretDto({required this.clientSecret});

  factory DepositSecretDto.fromJson(Map<String, dynamic> json) =>
      DepositSecretDto(clientSecret: json['client_secret'] as String);
}

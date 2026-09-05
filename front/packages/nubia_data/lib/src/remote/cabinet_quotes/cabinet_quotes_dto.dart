import 'package:nubia_domain/src/entities/cabinet_quote.dart';
import 'package:nubia_domain/src/entities/quote.dart';

class CabinetQuoteDto {
  final String id;

  /// Voir `CabinetQuote.quoteRef` (#6370). Absent des payloads antérieurs à
  /// la migration 0257 → retombe sur [id] (rétrocompat).
  final String quoteRef;
  final String cabinetId;
  final String patientId;
  final String patientName;
  final int totalCents;
  final int patientShareCents;
  final String status;
  final String createdAt;
  final String? signedAt;
  final String? expiresAt;

  /// `quote.deposit_paid` (migration 0093, #5094) : acompte réglé, sans que
  /// `status` (brut back) ne passe par un statut `paid` — celui-ci n'existe
  /// pas côté back (`VALID_QUOTE_STATUSES`). Absent des réponses avant #5094
  /// → `false` par défaut (rétrocompat).
  final bool depositPaid;

  /// Lignes du devis — présentes uniquement sur le détail
  /// (`GET /v1/cabinet/quotes/:id`), absentes de la liste.
  final List<QuoteLineItem>? items;

  const CabinetQuoteDto({
    required this.id,
    required this.quoteRef,
    required this.cabinetId,
    required this.patientId,
    required this.patientName,
    required this.totalCents,
    required this.patientShareCents,
    required this.status,
    required this.createdAt,
    this.signedAt,
    this.expiresAt,
    this.depositPaid = false,
    this.items,
  });

  factory CabinetQuoteDto.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'] as List<dynamic>?;
    final id = json['id'] as String;
    return CabinetQuoteDto(
      id: id,
      quoteRef: json['quote_ref'] as String? ?? id,
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
      depositPaid: json['deposit_paid'] as bool? ?? false,
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
        quoteRef: quoteRef,
        cabinetId: cabinetId,
        patientId: patientId,
        patientName: patientName,
        totalCents: totalCents,
        patientShareCents: patientShareCents,
        status: parseStatus(status, depositPaid: depositPaid),
        createdAt: DateTime.parse(createdAt),
        signedAt: signedAt != null ? DateTime.parse(signedAt!) : null,
        expiresAt: expiresAt != null ? DateTime.parse(expiresAt!) : null,
        items: items,
      );

  /// `depositPaid` (#5094) : le back n'a pas de statut `paid` distinct
  /// (`VALID_QUOTE_STATUSES` côté API n'inclut que
  /// draft/sent/signed/refused/expired) — un devis `signed` dont l'acompte
  /// est réglé (`quote.deposit_paid`) est remonté côté domaine comme
  /// [CabinetQuoteStatus.paid] plutôt que [CabinetQuoteStatus.signed].
  static CabinetQuoteStatus parseStatus(
    String value, {
    bool depositPaid = false,
  }) {
    switch (value) {
      case 'draft':
        return CabinetQuoteStatus.draft;
      case 'sent':
        return CabinetQuoteStatus.sent;
      case 'signed':
        return depositPaid
            ? CabinetQuoteStatus.paid
            : CabinetQuoteStatus.signed;
      case 'expired':
        return CabinetQuoteStatus.expired;
      case 'cancelled':
        return CabinetQuoteStatus.cancelled;
      default:
        return CabinetQuoteStatus.draft;
    }
  }
}

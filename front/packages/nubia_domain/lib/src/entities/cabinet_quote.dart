import 'package:equatable/equatable.dart';
import 'package:nubia_domain/src/entities/quote.dart';

/// `paid` (#5094) : dérivé de `signed` + `quote.deposit_paid` (acompte réglé),
/// pas un statut back distinct — voir `CabinetQuoteDto.parseStatus`.
enum CabinetQuoteStatus { draft, sent, signed, paid, expired, cancelled }

/// Devis côté cabinet (vue pro).
/// Source : GET /v1/cabinet/quotes
class CabinetQuote extends Equatable {
  final String id;

  /// Référence lisible/prononçable (`DEV-0042`, migration 0257, #6370) —
  /// à afficher partout où [id] (UUID technique) l'était côté secrétariat.
  final String quoteRef;
  final String cabinetId;
  final String patientId;
  final String patientName;
  final int totalCents;
  final int patientShareCents;
  final CabinetQuoteStatus status;
  final DateTime createdAt;
  final DateTime? signedAt;
  final DateTime? expiresAt;
  final List<QuoteLineItem>? items;

  const CabinetQuote({
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
    this.items,
  });

  bool get isSigned => status == CabinetQuoteStatus.signed;
  bool get isExpired => expiresAt?.isBefore(DateTime.now()) ?? false;

  @override
  List<Object?> get props => [id, status];
}

import 'package:equatable/equatable.dart';

enum CabinetQuoteStatus { draft, sent, signed, expired, cancelled }

/// Devis côté cabinet (vue pro).
/// Source : GET /v1/cabinet/quotes
class CabinetQuote extends Equatable {
  final String id;
  final String cabinetId;
  final String patientId;
  final String patientName;
  final int totalCents;
  final int patientShareCents;
  final CabinetQuoteStatus status;
  final DateTime createdAt;
  final DateTime? signedAt;
  final DateTime? expiresAt;

  const CabinetQuote({
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
  });

  bool get isSigned => status == CabinetQuoteStatus.signed;
  bool get isExpired => expiresAt?.isBefore(DateTime.now()) ?? false;

  @override
  List<Object?> get props => [id, status];
}

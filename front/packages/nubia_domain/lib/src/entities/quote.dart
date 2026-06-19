import 'package:equatable/equatable.dart';

enum QuoteStatus { draft, sent, signed, expired, cancelled }

class QuoteLineItem extends Equatable {
  final String id;
  final String label;
  final String? ccamCode;
  final String? toothLabel; // e.g. "11", "46"
  final int totalCents;
  final int amoShareCents;   // Remboursement Sécu
  final int amcShareCents;   // Remboursement Mutuelle
  final int patientShareCents; // Reste à charge

  const QuoteLineItem({
    required this.id,
    required this.label,
    this.ccamCode,
    this.toothLabel,
    required this.totalCents,
    required this.amoShareCents,
    required this.amcShareCents,
    required this.patientShareCents,
  });

  @override
  List<Object?> get props => [id];
}

class Quote extends Equatable {
  final String id;
  final String cabinetId;
  final String practitionerName;
  final List<QuoteLineItem> items;
  final int totalCents;
  final int patientShareCents; // total reste à charge
  final int depositCents;      // acompte demandé
  final QuoteStatus status;
  final DateTime createdAt;
  final DateTime? signedAt;
  final DateTime? expiresAt;
  final String? documentId; // signed PDF in vault

  const Quote({
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

  bool get canSign => status == QuoteStatus.sent;
  bool get isExpired => expiresAt?.isBefore(DateTime.now()) ?? false;

  @override
  List<Object?> get props => [id, status];
}

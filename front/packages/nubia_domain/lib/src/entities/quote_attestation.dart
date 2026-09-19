import 'package:equatable/equatable.dart';

/// Attestation d'information déposée sur un devis, à faire signer au
/// patient avant que celui-ci puisse signer le devis (#7202/#7203).
/// Source : `GET/POST /v1/cabinet/quotes/:id/attestation`.
class QuoteAttestation extends Equatable {
  final String id;
  final String body;
  final DateTime? signedAt;
  final DateTime createdAt;

  const QuoteAttestation({
    required this.id,
    required this.body,
    this.signedAt,
    required this.createdAt,
  });

  bool get isSigned => signedAt != null;

  @override
  List<Object?> get props => [id, signedAt];
}

import 'package:equatable/equatable.dart';

/// Nature d'une pièce jointe de devis (#7202/#7203).
enum QuoteAttachmentKind {
  consent,
  prescription,
  letter,
  other;

  String toApi() => switch (this) {
        QuoteAttachmentKind.consent => 'consent',
        QuoteAttachmentKind.prescription => 'prescription',
        QuoteAttachmentKind.letter => 'letter',
        QuoteAttachmentKind.other => 'other',
      };

  static QuoteAttachmentKind fromApi(String value) => switch (value) {
        'consent' => QuoteAttachmentKind.consent,
        'prescription' => QuoteAttachmentKind.prescription,
        'letter' => QuoteAttachmentKind.letter,
        _ => QuoteAttachmentKind.other,
      };
}

/// Pièce jointe rattachée à un devis avant son envoi (#7203) : soit un
/// document déjà numérisé dans le dossier patient (`documentId` —
/// consentement, ordonnance…), soit un modèle de courrier pas encore
/// matérialisé (`templateRef`) — jamais les deux à la fois.
/// Source : `GET/POST /v1/cabinet/quotes/:id/attachments`.
class QuoteAttachment extends Equatable {
  final String id;
  final QuoteAttachmentKind kind;
  final String? documentId;
  final String? templateRef;
  final DateTime createdAt;

  const QuoteAttachment({
    required this.id,
    required this.kind,
    this.documentId,
    this.templateRef,
    required this.createdAt,
  });

  @override
  List<Object?> get props => [id];
}

import 'package:nubia_domain/src/entities/quote_attachment.dart';

class QuoteAttachmentDto {
  final String id;
  final String kind;
  final String? documentId;
  final String? templateRef;
  final String createdAt;

  const QuoteAttachmentDto({
    required this.id,
    required this.kind,
    this.documentId,
    this.templateRef,
    required this.createdAt,
  });

  factory QuoteAttachmentDto.fromJson(Map<String, dynamic> json) =>
      QuoteAttachmentDto(
        id: json['id'] as String,
        kind: json['kind'] as String,
        documentId: json['document_id'] as String?,
        templateRef: json['template_ref'] as String?,
        createdAt: json['created_at'] as String,
      );

  QuoteAttachment toDomain() => QuoteAttachment(
        id: id,
        kind: QuoteAttachmentKind.fromApi(kind),
        documentId: documentId,
        templateRef: templateRef,
        createdAt: DateTime.parse(createdAt),
      );
}

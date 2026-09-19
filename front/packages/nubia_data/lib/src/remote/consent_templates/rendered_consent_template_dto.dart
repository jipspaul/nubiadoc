import 'package:nubia_domain/src/entities/rendered_consent_template.dart';

class RenderedConsentTemplateDto {
  final String documentId;
  final String filename;
  final int sizeBytes;
  final String body;

  const RenderedConsentTemplateDto({
    required this.documentId,
    required this.filename,
    required this.sizeBytes,
    required this.body,
  });

  factory RenderedConsentTemplateDto.fromJson(Map<String, dynamic> json) {
    return RenderedConsentTemplateDto(
      documentId: json['document_id'] as String,
      filename: json['filename'] as String,
      sizeBytes: json['size_bytes'] as int,
      body: json['body'] as String,
    );
  }

  RenderedConsentTemplate toDomain() => RenderedConsentTemplate(
        documentId: documentId,
        filename: filename,
        sizeBytes: sizeBytes,
        body: body,
      );
}

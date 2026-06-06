import 'package:nubia_patient/domain/entities/document.dart';

class DocumentDto {
  final String id;
  final String category;
  final String filename;
  final String mimeType;
  final int fileSizeBytes;
  final String createdAt;
  final String? sha256;

  const DocumentDto({
    required this.id,
    required this.category,
    required this.filename,
    required this.mimeType,
    required this.fileSizeBytes,
    required this.createdAt,
    this.sha256,
  });

  factory DocumentDto.fromJson(Map<String, dynamic> json) => DocumentDto(
        id: json['id'] as String,
        category: json['category'] as String,
        filename: json['filename'] as String,
        mimeType: json['mime_type'] as String,
        fileSizeBytes: (json['file_size_bytes'] as num?)?.toInt() ??
            (json['size'] as num?)?.toInt() ??
            0,
        createdAt: json['created_at'] as String,
        sha256: json['sha256'] as String?,
      );

  Document toDomain() => Document(
        id: id,
        name: filename,
        category: _parseCategory(category),
        createdAt: DateTime.parse(createdAt),
        fileSizeBytes: fileSizeBytes,
        mimeType: mimeType,
        sha256: sha256,
      );

  static DocumentCategory _parseCategory(String raw) {
    switch (raw) {
      case 'devis':
        return DocumentCategory.quote;
      case 'facture':
        return DocumentCategory.invoice;
      case 'ordonnance':
        return DocumentCategory.prescription;
      case 'radio':
        return DocumentCategory.xray;
      case 'cbct':
        return DocumentCategory.cbct;
      case 'photo':
        return DocumentCategory.photo;
      case 'cr':
        return DocumentCategory.report;
      case 'consentement':
        return DocumentCategory.consent;
      case 'consigne':
      case 'attestation':
        return DocumentCategory.instructions;
      case 'carte_mutuelle':
        return DocumentCategory.mutualCard;
      default:
        return DocumentCategory.other;
    }
  }
}

class DocumentSignedUrlDto {
  final String url;

  const DocumentSignedUrlDto({required this.url});

  factory DocumentSignedUrlDto.fromJson(Map<String, dynamic> json) =>
      DocumentSignedUrlDto(url: json['url'] as String);
}

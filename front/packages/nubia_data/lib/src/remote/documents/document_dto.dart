import 'package:nubia_domain/src/entities/document.dart';

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
        // Contrat réel : le champ est `size_bytes` (api/src/documents.rs,
        // DocumentDetail). On garde les anciens noms en repli par sûreté.
        fileSizeBytes: (json['size_bytes'] as num?)?.toInt() ??
            (json['file_size_bytes'] as num?)?.toInt() ??
            (json['size'] as num?)?.toInt() ??
            0,
        createdAt: json['created_at'] as String,
        sha256: json['sha256'] as String?,
      );

  /// Réponse de `POST /documents` (upload).
  ///
  /// Le back ne renvoie que `{document_id, category, filename, size_bytes,
  /// sha256}` (`api/src/documents.rs` `UploadDocumentResponse`) — pas de
  /// `id`/`mime_type`/`created_at`. `DocumentDto.fromJson` levait un
  /// `TypeError` sur ce payload (`json['id']` → null as String), catché en
  /// `ParseFailure` générique : un upload RÉUSSI (201) affichait « Erreur de
  /// décodage de la réponse. » et poussait au ré-upload → doublons (#3831).
  /// `mimeType`/`filename` viennent de la requête elle-même (connus par
  /// l'appelant, jamais absents) plutôt que d'un champ que l'API ne renvoie pas.
  factory DocumentDto.fromUploadResponse(
    Map<String, dynamic> json, {
    required String filename,
    required String mimeType,
  }) =>
      DocumentDto(
        id: (json['document_id'] as String?) ?? (json['id'] as String),
        category: json['category'] as String,
        filename: (json['filename'] as String?) ?? filename,
        mimeType: mimeType,
        fileSizeBytes: (json['size_bytes'] as num?)?.toInt() ?? 0,
        createdAt: DateTime.now().toIso8601String(),
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
      case 'carte_vitale':
        return DocumentCategory.vitalCard;
      default:
        return DocumentCategory.other;
    }
  }
}

class DocumentSignedUrlDto {
  final String url;

  const DocumentSignedUrlDto({required this.url});

  // L'API `GET /v1/documents/:id/download` renvoie `{"download_url": ...}`
  // (cf. api/src/documents.rs DownloadUrlResponse). On lit donc `download_url`
  // en priorité ; fallback `url` par tolérance (redirection 302 / évolution).
  // Avant : `json['url']` seul → null → « Erreur de décodage de la réponse »
  // à l'ouverture d'un document (JEL-25).
  factory DocumentSignedUrlDto.fromJson(Map<String, dynamic> json) =>
      DocumentSignedUrlDto(
        url: (json['download_url'] ?? json['url']) as String,
      );
}

import 'package:nubia_domain/src/entities/generated_letter.dart';

class GeneratedLetterDto {
  final String documentId;
  final String filename;
  final int sizeBytes;
  final String body;

  const GeneratedLetterDto({
    required this.documentId,
    required this.filename,
    required this.sizeBytes,
    required this.body,
  });

  factory GeneratedLetterDto.fromJson(Map<String, dynamic> json) =>
      GeneratedLetterDto(
        documentId: json['document_id'] as String,
        filename: json['filename'] as String,
        sizeBytes: json['size_bytes'] as int,
        body: json['body'] as String,
      );

  GeneratedLetter toDomain() => GeneratedLetter(
        documentId: documentId,
        filename: filename,
        sizeBytes: sizeBytes,
        body: body,
      );
}

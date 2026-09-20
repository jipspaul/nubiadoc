import 'package:nubia_domain/src/entities/custom_device_declaration_result.dart';

class CustomDeviceDeclarationDto {
  final String declarationId;
  final String documentId;
  final String filename;
  final int sizeBytes;

  const CustomDeviceDeclarationDto({
    required this.declarationId,
    required this.documentId,
    required this.filename,
    required this.sizeBytes,
  });

  factory CustomDeviceDeclarationDto.fromJson(Map<String, dynamic> json) =>
      CustomDeviceDeclarationDto(
        declarationId: json['declaration_id'] as String,
        documentId: json['document_id'] as String,
        filename: json['filename'] as String,
        sizeBytes: json['size_bytes'] as int,
      );

  CustomDeviceDeclarationResult toDomain() => CustomDeviceDeclarationResult(
        declarationId: declarationId,
        documentId: documentId,
        filename: filename,
        sizeBytes: sizeBytes,
      );
}

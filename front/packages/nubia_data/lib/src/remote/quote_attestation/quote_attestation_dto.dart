import 'package:nubia_domain/src/entities/quote_attestation.dart';

class QuoteAttestationDto {
  final String id;
  final String body;
  final String? signedAt;
  final String createdAt;

  const QuoteAttestationDto({
    required this.id,
    required this.body,
    this.signedAt,
    required this.createdAt,
  });

  factory QuoteAttestationDto.fromJson(Map<String, dynamic> json) =>
      QuoteAttestationDto(
        id: json['id'] as String,
        body: json['body'] as String,
        signedAt: json['signed_at'] as String?,
        createdAt: json['created_at'] as String,
      );

  QuoteAttestation toDomain() => QuoteAttestation(
        id: id,
        body: body,
        signedAt: signedAt != null ? DateTime.parse(signedAt!) : null,
        createdAt: DateTime.parse(createdAt),
      );
}

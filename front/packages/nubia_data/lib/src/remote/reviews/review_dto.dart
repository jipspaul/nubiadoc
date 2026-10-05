import 'package:nubia_domain/src/entities/review.dart';

class ReviewDto {
  final String id;
  final String providerId;
  final String? appointmentId;
  final int rating;
  final String? comment;
  final String authorName;
  final String createdAt;
  final String status;

  const ReviewDto({
    required this.id,
    required this.providerId,
    this.appointmentId,
    required this.rating,
    this.comment,
    required this.authorName,
    required this.createdAt,
    required this.status,
  });

  factory ReviewDto.fromJson(Map<String, dynamic> json) => ReviewDto(
        id: json['id'] as String,
        providerId: json['provider_id'] as String,
        appointmentId: json['appointment_id'] as String?,
        rating: (json['rating'] as num).toInt(),
        comment: json['comment'] as String?,
        authorName: json['author_name'] as String,
        createdAt: json['created_at'] as String,
        status: json['status'] as String? ?? 'published',
      );

  Review toDomain() => Review(
        id: id,
        providerId: providerId,
        appointmentId: appointmentId,
        rating: rating,
        comment: comment,
        authorName: authorName,
        createdAt: DateTime.parse(createdAt),
        status: reviewStatusFromString(status),
      );
}

ReviewStatus reviewStatusFromString(String value) {
  switch (value) {
    case 'published':
      return ReviewStatus.published;
    case 'rejected':
      return ReviewStatus.rejected;
    default:
      return ReviewStatus.pending;
  }
}

/// Réponse (réelle) de `POST /v1/reviews` — distincte de [ReviewDto], qui
/// modélise la lecture d'un avis. L'API ne renvoie que l'identifiant créé et
/// le statut (`api/src/reviews.rs::CreateReviewResponse`), pas les autres
/// champs d'un avis (#6908 : réutiliser `ReviewDto.fromJson` ici fait
/// planter le décodage, 201 alors affiché comme une erreur).
class CreateReviewResponseDto {
  final String id;
  final String status;

  const CreateReviewResponseDto({required this.id, required this.status});

  factory CreateReviewResponseDto.fromJson(Map<String, dynamic> json) =>
      CreateReviewResponseDto(
        id: json['review_id'] as String,
        status: json['status'] as String,
      );
}

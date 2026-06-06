import 'package:nubia_patient/domain/entities/review.dart';

class ReviewDto {
  final String id;
  final String providerId;
  final String appointmentId;
  final int rating;
  final String? comment;
  final String authorName;
  final String createdAt;
  final String status;

  const ReviewDto({
    required this.id,
    required this.providerId,
    required this.appointmentId,
    required this.rating,
    this.comment,
    required this.authorName,
    required this.createdAt,
    required this.status,
  });

  factory ReviewDto.fromJson(Map<String, dynamic> json) => ReviewDto(
        id: json['id'] as String,
        providerId: json['provider_id'] as String,
        appointmentId: json['appointment_id'] as String,
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
        status: _parseStatus(status),
      );

  static ReviewStatus _parseStatus(String value) {
    switch (value) {
      case 'published':
        return ReviewStatus.published;
      case 'rejected':
        return ReviewStatus.rejected;
      default:
        return ReviewStatus.pending;
    }
  }
}

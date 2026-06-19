import 'package:equatable/equatable.dart';

enum ReviewStatus { pending, published, rejected }

class Review extends Equatable {
  final String id;
  final String providerId;
  final String appointmentId;
  final int rating; // 1..5
  final String? comment;
  final String authorName;
  final DateTime createdAt;
  final ReviewStatus status;

  const Review({
    required this.id,
    required this.providerId,
    required this.appointmentId,
    required this.rating,
    this.comment,
    required this.authorName,
    required this.createdAt,
    required this.status,
  });

  @override
  List<Object?> get props => [id, rating, status];
}

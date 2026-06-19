import 'package:equatable/equatable.dart';

sealed class ReviewsEvent extends Equatable {
  const ReviewsEvent();

  @override
  List<Object?> get props => [];
}

final class ReviewsLoadRequested extends ReviewsEvent {
  final String providerId;

  const ReviewsLoadRequested(this.providerId);

  @override
  List<Object?> get props => [providerId];
}

final class ReviewSubmitRequested extends ReviewsEvent {
  final String appointmentId;
  final int rating;
  final String? comment;
  final String idempotencyKey;

  const ReviewSubmitRequested({
    required this.appointmentId,
    required this.rating,
    this.comment,
    required this.idempotencyKey,
  });

  @override
  List<Object?> get props => [appointmentId, rating, idempotencyKey];
}

import 'package:equatable/equatable.dart';
import 'package:nubia_domain/nubia_domain.dart';

sealed class ReviewsState extends Equatable {
  const ReviewsState();

  @override
  List<Object?> get props => [];
}

final class ReviewsInitial extends ReviewsState {
  const ReviewsInitial();
}

final class ReviewsLoading extends ReviewsState {
  const ReviewsLoading();
}

final class ReviewsLoaded extends ReviewsState {
  final List<Review> reviews;

  const ReviewsLoaded(this.reviews);

  @override
  List<Object?> get props => [reviews];
}

final class ReviewsError extends ReviewsState {
  final String message;
  final String providerId;

  const ReviewsError(this.message, {required this.providerId});

  @override
  List<Object?> get props => [message, providerId];
}

final class ReviewSubmitting extends ReviewsState {
  const ReviewSubmitting();
}

final class ReviewSubmitSuccess extends ReviewsState {
  const ReviewSubmitSuccess();
}

final class ReviewSubmitFailure extends ReviewsState {
  final String message;

  const ReviewSubmitFailure(this.message);

  @override
  List<Object?> get props => [message];
}

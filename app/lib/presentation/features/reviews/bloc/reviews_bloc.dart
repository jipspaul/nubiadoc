import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:injectable/injectable.dart';
import 'package:nubia_patient/domain/entities/review.dart';
import 'package:nubia_patient/domain/usecases/reviews/get_provider_reviews_use_case.dart';
import 'package:nubia_patient/domain/usecases/reviews/submit_review_use_case.dart';

// ---------------------------------------------------------------------------
// Events
// ---------------------------------------------------------------------------

abstract class ReviewsEvent extends Equatable {
  const ReviewsEvent();

  @override
  List<Object?> get props => [];
}

class ReviewsLoadRequested extends ReviewsEvent {
  final String providerId;

  const ReviewsLoadRequested(this.providerId);

  @override
  List<Object?> get props => [providerId];
}

class ReviewSubmitRequested extends ReviewsEvent {
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

// ---------------------------------------------------------------------------
// States
// ---------------------------------------------------------------------------

abstract class ReviewsState extends Equatable {
  const ReviewsState();

  @override
  List<Object?> get props => [];
}

class ReviewsInitial extends ReviewsState {
  const ReviewsInitial();
}

class ReviewsLoading extends ReviewsState {
  const ReviewsLoading();
}

class ReviewsLoaded extends ReviewsState {
  final List<Review> reviews;

  const ReviewsLoaded(this.reviews);

  @override
  List<Object?> get props => [reviews];
}

class ReviewsError extends ReviewsState {
  final String message;

  const ReviewsError(this.message);

  @override
  List<Object?> get props => [message];
}

class ReviewSubmitting extends ReviewsState {
  const ReviewSubmitting();
}

class ReviewSubmitSuccess extends ReviewsState {
  const ReviewSubmitSuccess();
}

class ReviewSubmitFailure extends ReviewsState {
  final String message;

  const ReviewSubmitFailure(this.message);

  @override
  List<Object?> get props => [message];
}

// ---------------------------------------------------------------------------
// Bloc
// ---------------------------------------------------------------------------

@injectable
class ReviewsBloc extends Bloc<ReviewsEvent, ReviewsState> {
  final GetProviderReviewsUseCase _getProviderReviews;
  final SubmitReviewUseCase _submitReview;

  ReviewsBloc(this._getProviderReviews, this._submitReview)
      : super(const ReviewsInitial()) {
    on<ReviewsLoadRequested>(_onLoadRequested);
    on<ReviewSubmitRequested>(_onSubmitRequested);
  }

  Future<void> _onLoadRequested(
    ReviewsLoadRequested event,
    Emitter<ReviewsState> emit,
  ) async {
    emit(const ReviewsLoading());
    final result = await _getProviderReviews(event.providerId);
    result.fold(
      (failure) => emit(ReviewsError(failure.message)),
      (reviews) => emit(ReviewsLoaded(reviews)),
    );
  }

  Future<void> _onSubmitRequested(
    ReviewSubmitRequested event,
    Emitter<ReviewsState> emit,
  ) async {
    emit(const ReviewSubmitting());
    final result = await _submitReview(
      appointmentId: event.appointmentId,
      rating: event.rating,
      comment: event.comment,
      idempotencyKey: event.idempotencyKey,
    );
    result.fold(
      (failure) => emit(ReviewSubmitFailure(failure.message)),
      (_) => emit(const ReviewSubmitSuccess()),
    );
  }
}

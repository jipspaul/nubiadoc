import 'package:bloc/bloc.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'reviews_event.dart';
import 'reviews_state.dart';

class ReviewsBloc extends Bloc<ReviewsEvent, ReviewsState> {
  final GetProviderReviewsUseCase _getProviderReviews;
  final SubmitReviewUseCase _submitReview;

  ReviewsBloc({
    required GetProviderReviewsUseCase getProviderReviews,
    required SubmitReviewUseCase submitReview,
  })  : _getProviderReviews = getProviderReviews,
        _submitReview = submitReview,
        super(const ReviewsInitial()) {
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

import 'package:bloc/bloc.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'reviews_event.dart';
import 'reviews_state.dart';

class ReviewsBloc extends Bloc<ReviewsEvent, ReviewsState> with SafeEmitMixin<ReviewsState> {
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
    try {
      final result = await _getProviderReviews(event.providerId);
      result.fold(
        (failure) => safeEmit(ReviewsError(failure.message)),
        (reviews) => safeEmit(ReviewsLoaded(reviews)),
      );
    } catch (_) {
      safeEmit(const ReviewsError('Erreur de chargement.'));
    }
  }

  Future<void> _onSubmitRequested(
    ReviewSubmitRequested event,
    Emitter<ReviewsState> emit,
  ) async {
    emit(const ReviewSubmitting());
    try {
      final result = await _submitReview(
        appointmentId: event.appointmentId,
        rating: event.rating,
        comment: event.comment,
        idempotencyKey: event.idempotencyKey,
      );
      result.fold(
        (failure) => safeEmit(ReviewSubmitFailure(failure.message)),
        (_) => safeEmit(const ReviewSubmitSuccess()),
      );
    } catch (_) {
      safeEmit(const ReviewSubmitFailure('Erreur lors de l\'envoi.'));
    }
  }
}

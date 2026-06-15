import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/review.dart';
import 'package:nubia_domain/src/repositories/review_repository.dart';

class SubmitReviewUseCase {
  final ReviewRepository _repository;

  const SubmitReviewUseCase(this._repository);

  Future<Either<Failure, Review>> call({
    required String appointmentId,
    required int rating,
    String? comment,
    required String idempotencyKey,
  }) =>
      _repository.submitReview(
        appointmentId: appointmentId,
        rating: rating,
        comment: comment,
        idempotencyKey: idempotencyKey,
      );
}

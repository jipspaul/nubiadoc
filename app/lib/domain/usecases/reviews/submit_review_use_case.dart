import 'package:dartz/dartz.dart';
import 'package:injectable/injectable.dart';
import 'package:nubia_patient/core/error/failure.dart';
import 'package:nubia_patient/domain/entities/review.dart';
import 'package:nubia_patient/domain/repositories/review_repository.dart';

@injectable
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

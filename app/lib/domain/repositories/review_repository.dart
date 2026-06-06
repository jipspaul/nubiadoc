import 'package:dartz/dartz.dart';
import 'package:nubia_patient/core/error/failure.dart';
import 'package:nubia_patient/domain/entities/review.dart';

abstract class ReviewRepository {
  Future<Either<Failure, List<Review>>> getProviderReviews(String providerId);
  Future<Either<Failure, Review>> submitReview({
    required String appointmentId,
    required int rating,
    String? comment,
    required String idempotencyKey,
  });
}

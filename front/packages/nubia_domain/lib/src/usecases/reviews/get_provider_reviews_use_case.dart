import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/review.dart';
import 'package:nubia_domain/src/repositories/review_repository.dart';

class GetProviderReviewsUseCase {
  final ReviewRepository _repository;

  const GetProviderReviewsUseCase(this._repository);

  Future<Either<Failure, List<Review>>> call(String providerId) =>
      _repository.getProviderReviews(providerId);
}

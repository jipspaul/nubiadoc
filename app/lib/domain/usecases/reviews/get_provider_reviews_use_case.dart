import 'package:dartz/dartz.dart';
import 'package:injectable/injectable.dart';
import 'package:nubia_patient/core/error/failure.dart';
import 'package:nubia_patient/domain/entities/review.dart';
import 'package:nubia_patient/domain/repositories/review_repository.dart';

@injectable
class GetProviderReviewsUseCase {
  final ReviewRepository _repository;

  const GetProviderReviewsUseCase(this._repository);

  Future<Either<Failure, List<Review>>> call(String providerId) =>
      _repository.getProviderReviews(providerId);
}

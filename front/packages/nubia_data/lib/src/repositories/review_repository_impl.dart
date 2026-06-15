import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_data/src/remote/reviews/review_api.dart';
import 'package:nubia_domain/src/entities/review.dart';
import 'package:nubia_domain/src/repositories/review_repository.dart';

class ReviewRepositoryImpl implements ReviewRepository {
  final ReviewApi _api;

  const ReviewRepositoryImpl(this._api);

  @override
  Future<Either<Failure, List<Review>>> getProviderReviews(
    String providerId,
  ) async {
    try {
      final dtos = await _api.getProviderReviews(providerId);
      return Right(dtos.map((d) => d.toDomain()).toList());
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      if (e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.connectionTimeout) {
        return const Left(OfflineFailure());
      }
      return Left(ServerFailure(
        message: 'Erreur lors de la récupération des avis.',
        statusCode: e.response?.statusCode,
      ));
    }
  }

  @override
  Future<Either<Failure, Review>> submitReview({
    required String appointmentId,
    required int rating,
    String? comment,
    required String idempotencyKey,
  }) async {
    try {
      final dto = await _api.submitReview(
        appointmentId: appointmentId,
        rating: rating,
        comment: comment,
        idempotencyKey: idempotencyKey,
      );
      return Right(dto.toDomain());
    } on DioException catch (e) {
      final statusCode = e.response?.statusCode;
      final apiCode = e.response?.data is Map
          ? (e.response!.data as Map)['code'] as String?
          : null;
      if (statusCode == 422 && apiCode == 'appointment_not_eligible') {
        return const Left(ValidationFailure(
          message: 'Ce rendez-vous ne peut pas faire l\'objet d\'un avis.',
        ));
      }
      if (statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      return Left(ServerFailure(
        message: 'Erreur lors de la soumission de l\'avis.',
        statusCode: statusCode,
      ));
    }
  }
}

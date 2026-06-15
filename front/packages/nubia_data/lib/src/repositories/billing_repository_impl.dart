import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_data/src/remote/billing/billing_api.dart';
import 'package:nubia_domain/src/entities/quote.dart';
import 'package:nubia_domain/src/repositories/billing_repository.dart';

class BillingRepositoryImpl implements BillingRepository {
  final BillingApi _api;

  const BillingRepositoryImpl(this._api);

  @override
  Future<Either<Failure, List<Quote>>> getQuotes() async {
    try {
      final dtos = await _api.getQuotes();
      return Right(dtos.map((d) => d.toDomain()).toList());
    } on DioException catch (e) {
      return Left(_mapDioError(e, 'Erreur lors du chargement des devis.'));
    }
  }

  @override
  Future<Either<Failure, Quote>> getQuoteById(String id) async {
    try {
      final dto = await _api.getQuoteById(id);
      return Right(dto.toDomain());
    } on DioException catch (e) {
      return Left(_mapDioError(e, 'Devis introuvable.'));
    }
  }

  @override
  Future<Either<Failure, String>> initiateSignature(String quoteId) async {
    try {
      final dto = await _api.initiateSignature(quoteId);
      return Right(dto.redirectUrl);
    } on DioException catch (e) {
      return Left(_mapDioError(e, 'Erreur lors de l\'initiation de la signature.'));
    }
  }

  @override
  Future<Either<Failure, Quote>> confirmSignature(String quoteId) async {
    try {
      final dto = await _api.confirmSignature(quoteId);
      return Right(dto.toDomain());
    } on DioException catch (e) {
      return Left(_mapDioError(e, 'Erreur lors de la confirmation de la signature.'));
    }
  }

  @override
  Future<Either<Failure, String>> initiateDeposit({
    required String quoteId,
    required String idempotencyKey,
  }) async {
    try {
      final dto = await _api.initiateDeposit(
        quoteId: quoteId,
        idempotencyKey: idempotencyKey,
      );
      return Right(dto.clientSecret);
    } on DioException catch (e) {
      return Left(_mapDioError(e, 'Erreur lors de l\'initiation du paiement.'));
    }
  }

  Failure _mapDioError(DioException e, String defaultMessage) {
    if (e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.connectionTimeout) {
      return const OfflineFailure();
    }
    if (e.response?.statusCode == 401) return const UnauthorizedFailure();
    if (e.response?.statusCode == 404) return const NotFoundFailure();
    return ServerFailure(
      message: defaultMessage,
      statusCode: e.response?.statusCode,
    );
  }
}

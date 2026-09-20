import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_data/src/remote/quote_events/quote_events_api.dart';
import 'package:nubia_domain/src/entities/quote_event.dart';
import 'package:nubia_domain/src/repositories/quote_events_repository.dart';

class QuoteEventsRepositoryImpl implements QuoteEventsRepository {
  final QuoteEventsApi _api;

  const QuoteEventsRepositoryImpl(this._api);

  @override
  Future<Either<Failure, List<QuoteEvent>>> listCabinetEvents(
    String quoteId,
  ) async {
    try {
      final dtos = await _api.listCabinetEvents(quoteId);
      return Right(dtos.map((d) => d.toDomain()).toList());
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        return const Left(NotFoundFailure('Devis introuvable.'));
      }
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      return Left(ServerFailure(
        message: 'Impossible de charger le suivi du devis.',
        statusCode: e.response?.statusCode,
      ));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }
}

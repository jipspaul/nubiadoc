import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/quote_event.dart';

abstract class QuoteEventsRepository {
  /// `GET /v1/cabinet/quotes/:id/events` — timeline chronologique d'un
  /// devis, lisible secrétariat/praticien (#7467).
  Future<Either<Failure, List<QuoteEvent>>> listCabinetEvents(
    String quoteId,
  );
}

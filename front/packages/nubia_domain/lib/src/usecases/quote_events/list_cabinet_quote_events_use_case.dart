import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/quote_event.dart';
import 'package:nubia_domain/src/repositories/quote_events_repository.dart';

class ListCabinetQuoteEventsUseCase {
  final QuoteEventsRepository _repository;

  const ListCabinetQuoteEventsUseCase(this._repository);

  Future<Either<Failure, List<QuoteEvent>>> call(String quoteId) =>
      _repository.listCabinetEvents(quoteId);
}

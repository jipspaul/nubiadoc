import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/cabinet_quote.dart';
import 'package:nubia_domain/src/repositories/cabinet_quotes_repository.dart';

/// Envoie un devis (brouillon) au patient pour signature.
///
/// Déclenche `POST /v1/cabinet/quotes/:id/send` : le back passe le devis à
/// `sent`, le rendant visible côté patient. Retourne le statut confirmé.
class SendCabinetQuoteUseCase {
  final CabinetQuotesRepository _repository;

  const SendCabinetQuoteUseCase(this._repository);

  Future<Either<Failure, CabinetQuoteStatus>> call(String id) =>
      _repository.sendQuote(id);
}

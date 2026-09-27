import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/cabinet_quotes_repository.dart';

/// Relance un devis déjà `sent` en attente de signature.
///
/// Déclenche `POST /v1/cabinet/quotes/:id/remind` — contrairement à
/// [SendCabinetQuoteUseCase], réservé à l'envoi initial d'un brouillon
/// (idempotent une fois `sent`), cette route renotifie le patient (#6970).
class RemindCabinetQuoteUseCase {
  final CabinetQuotesRepository _repository;

  const RemindCabinetQuoteUseCase(this._repository);

  Future<Either<Failure, void>> call(String id) => _repository.remindQuote(id);
}

import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/cabinet_quote.dart';

abstract class CabinetQuotesRepository {
  Future<Either<Failure, List<CabinetQuote>>> list({int page = 1});
  Future<Either<Failure, CabinetQuote>> getById(String id);
  Future<Either<Failure, CabinetQuote>> create(CabinetQuote quote);
  Future<Either<Failure, CabinetQuote>> update(CabinetQuote quote);

  /// Envoie le devis (brouillon) au patient. Retourne le statut confirmé
  /// par le serveur (`sent`).
  Future<Either<Failure, CabinetQuoteStatus>> sendQuote(String id);
}

import 'package:dartz/dartz.dart';
import 'package:nubia_data/src/remote/pharmacy_quotes/pharmacy_quotes_api.dart';
import 'package:nubia_data/src/repositories/pharmacy_failure_mapper.dart';
import 'package:nubia_domain/src/entities/pharmacy_quote.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/pharmacy_quotes_repository.dart';

class PharmacyQuotesRepositoryImpl implements PharmacyQuotesRepository {
  final PharmacyQuotesApi _api;

  const PharmacyQuotesRepositoryImpl(this._api);

  @override
  Future<Either<Failure, List<PharmacyQuote>>> list() => guardPharmacyCall(
        () async => (await _api.list()).map((dto) => dto.toDomain()).toList(),
        errorMessage: 'Impossible de charger les devis.',
      );

  @override
  Future<Either<Failure, PharmacyQuote>> create({
    required String patientAccountId,
    required List<PharmacyQuoteItem> items,
    String? orderId,
  }) =>
      guardPharmacyCall(
        () async => (await _api.create(
          patientAccountId: patientAccountId,
          items: items,
          orderId: orderId,
        ))
            .toDomain(),
        errorMessage: 'Impossible de créer le devis.',
      );

  @override
  Future<Either<Failure, PharmacyQuote>> send(String id) => guardPharmacyCall(
        () async => (await _api.send(id)).toDomain(),
        errorMessage: 'Impossible d’envoyer le devis.',
      );

  @override
  Future<Either<Failure, PharmacyQuote>> decide(String id,
          {required bool accept}) =>
      guardPharmacyCall(
        () async => (await _api.decide(id, accept: accept)).toDomain(),
        errorMessage: 'Impossible d’enregistrer votre décision.',
      );
}

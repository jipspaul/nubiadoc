import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/entities/pharmacy_quote.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/pharmacy_quotes_repository.dart';

class CreatePharmacyQuoteUseCase {
  final PharmacyQuotesRepository _repository;

  const CreatePharmacyQuoteUseCase(this._repository);

  Future<Either<Failure, PharmacyQuote>> call({
    required String patientAccountId,
    required List<PharmacyQuoteItem> items,
    String? orderId,
  }) =>
      _repository.create(
        patientAccountId: patientAccountId,
        items: items,
        orderId: orderId,
      );
}

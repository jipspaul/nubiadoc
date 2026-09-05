import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/cabinet_quote.dart';
import 'package:nubia_domain/src/entities/quote.dart';
import 'package:nubia_domain/src/repositories/cabinet_quotes_repository.dart';

class UpdateCabinetQuoteUseCase {
  final CabinetQuotesRepository _repository;

  const UpdateCabinetQuoteUseCase(this._repository);

  Future<Either<Failure, CabinetQuote>> call({
    required String id,
    required List<QuoteLineItem> items,
  }) {
    final total = items.fold<int>(0, (sum, i) => sum + i.totalCents);
    final patientShare =
        items.fold<int>(0, (sum, i) => sum + i.patientShareCents);
    final quote = CabinetQuote(
      id: id,
      quoteRef: '',
      cabinetId: '',
      patientId: '',
      patientName: '',
      totalCents: total,
      patientShareCents: patientShare,
      status: CabinetQuoteStatus.draft,
      createdAt: DateTime.now(),
      items: items,
    );
    return _repository.update(quote);
  }
}

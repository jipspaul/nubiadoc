import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/invoice_reminder_repository.dart';

class SendInvoiceReminderUseCase {
  final InvoiceReminderRepository _repository;

  const SendInvoiceReminderUseCase(this._repository);

  Future<Either<Failure, void>> call(String invoiceId) =>
      _repository.send(invoiceId);
}

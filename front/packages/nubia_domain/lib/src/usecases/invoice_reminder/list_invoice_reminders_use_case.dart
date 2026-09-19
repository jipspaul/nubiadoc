import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/invoice_reminder.dart';
import 'package:nubia_domain/src/repositories/invoice_reminder_repository.dart';

class ListInvoiceRemindersUseCase {
  final InvoiceReminderRepository _repository;

  const ListInvoiceRemindersUseCase(this._repository);

  Future<Either<Failure, List<InvoiceReminder>>> call(String invoiceId) =>
      _repository.listHistory(invoiceId);
}

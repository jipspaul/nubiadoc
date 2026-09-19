import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/invoice_reminder.dart';

abstract class InvoiceReminderRepository {
  /// `POST /v1/invoices/:id/reminder` — relance le patient sur cette facture.
  Future<Either<Failure, void>> send(String invoiceId);

  /// `GET /v1/invoices/:id/reminders` — historique des relances déjà envoyées.
  Future<Either<Failure, List<InvoiceReminder>>> listHistory(
    String invoiceId,
  );
}

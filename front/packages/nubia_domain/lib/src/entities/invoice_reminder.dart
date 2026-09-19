import 'package:equatable/equatable.dart';

/// Canal effectivement utilisé pour délivrer une relance (#7205/#7206).
enum InvoiceReminderChannel {
  push,
  email,
  unknown;

  static InvoiceReminderChannel fromApi(String value) => switch (value) {
        'push' => InvoiceReminderChannel.push,
        'email' => InvoiceReminderChannel.email,
        _ => InvoiceReminderChannel.unknown,
      };
}

/// Une relance patient envoyée sur une facture (devis signé) impayée.
/// Source : `GET /v1/invoices/:id/reminders`.
class InvoiceReminder extends Equatable {
  final InvoiceReminderChannel channel;
  final DateTime sentAt;

  const InvoiceReminder({required this.channel, required this.sentAt});

  @override
  List<Object?> get props => [channel, sentAt];
}

import 'package:nubia_domain/src/entities/invoice_reminder.dart';

class InvoiceReminderDto {
  final String channel;
  final String sentAt;

  const InvoiceReminderDto({required this.channel, required this.sentAt});

  factory InvoiceReminderDto.fromJson(Map<String, dynamic> json) =>
      InvoiceReminderDto(
        channel: json['channel'] as String,
        sentAt: json['sent_at'] as String,
      );

  InvoiceReminder toDomain() => InvoiceReminder(
        channel: InvoiceReminderChannel.fromApi(channel),
        sentAt: DateTime.parse(sentAt),
      );
}

import 'package:nubia_domain/src/entities/lab_work_order.dart';

class LabWorkOrderDto {
  final String id;
  final String patientId;
  final String patientDisplayName;
  final String? quoteItemId;
  final String? toothFdi;
  final String? workNature;
  final String? appointmentId;
  final String labName;
  final int purchasePriceCents;
  final String status;
  final String sentAt;
  final String? expectedReturnAt;

  const LabWorkOrderDto({
    required this.id,
    required this.patientId,
    required this.patientDisplayName,
    this.quoteItemId,
    this.toothFdi,
    this.workNature,
    this.appointmentId,
    required this.labName,
    required this.purchasePriceCents,
    required this.status,
    required this.sentAt,
    this.expectedReturnAt,
  });

  factory LabWorkOrderDto.fromJson(Map<String, dynamic> json) =>
      LabWorkOrderDto(
        id: json['id'] as String,
        patientId: json['patient_id'] as String,
        patientDisplayName: json['patient_display_name'] as String,
        quoteItemId: json['quote_item_id'] as String?,
        toothFdi: json['tooth_fdi'] as String?,
        workNature: json['work_nature'] as String?,
        appointmentId: json['appointment_id'] as String?,
        labName: json['lab_name'] as String,
        purchasePriceCents: json['purchase_price_cents'] as int,
        status: json['status'] as String,
        sentAt: json['sent_at'] as String,
        expectedReturnAt: json['expected_return_at'] as String?,
      );

  LabWorkOrder toDomain() => LabWorkOrder(
        id: id,
        patientId: patientId,
        patientDisplayName: patientDisplayName,
        quoteItemId: quoteItemId,
        toothFdi: toothFdi,
        workNature: workNature,
        appointmentId: appointmentId,
        labName: labName,
        purchasePriceCents: purchasePriceCents,
        status: status,
        sentAt: sentAt,
        expectedReturnAt: expectedReturnAt,
      );
}

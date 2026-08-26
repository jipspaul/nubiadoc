import 'package:equatable/equatable.dart';

/// Un bon de travail prothétique (#4149). Source :
/// `GET /v1/cabinet/lab-work-orders`.
class LabWorkOrder extends Equatable {
  final String id;
  final String patientId;
  final String patientDisplayName;
  final String? quoteItemId;
  final String toothFdi;
  final String workNature;
  final String? appointmentId;
  final String labName;
  final int purchasePriceCents;
  final String status;
  final String sentAt;
  final String? expectedReturnAt;

  const LabWorkOrder({
    required this.id,
    required this.patientId,
    required this.patientDisplayName,
    this.quoteItemId,
    required this.toothFdi,
    required this.workNature,
    this.appointmentId,
    required this.labName,
    required this.purchasePriceCents,
    required this.status,
    required this.sentAt,
    this.expectedReturnAt,
  });

  LabWorkOrder copyWith({String? status}) => LabWorkOrder(
        id: id,
        patientId: patientId,
        patientDisplayName: patientDisplayName,
        quoteItemId: quoteItemId,
        toothFdi: toothFdi,
        workNature: workNature,
        appointmentId: appointmentId,
        labName: labName,
        purchasePriceCents: purchasePriceCents,
        status: status ?? this.status,
        sentAt: sentAt,
        expectedReturnAt: expectedReturnAt,
      );

  @override
  List<Object?> get props => [id, status];
}

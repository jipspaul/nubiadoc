import 'package:equatable/equatable.dart';

/// Un bon de travail prothétique (#4149). Source :
/// `GET /v1/cabinet/lab-work-orders`.
class LabWorkOrder extends Equatable {
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
  /// Date de pose (transition vers `fitted`, #6878) — `null` si le bon n'est
  /// pas encore posé.
  final String? fittedAt;

  const LabWorkOrder({
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
    this.fittedAt,
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
        fittedAt: fittedAt,
      );

  @override
  List<Object?> get props => [id, status];
}

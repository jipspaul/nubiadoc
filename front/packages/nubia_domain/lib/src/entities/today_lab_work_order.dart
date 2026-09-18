import 'package:equatable/equatable.dart';

/// Un bon de travail prothétique dont le RDV de pose tombe aujourd'hui ou
/// demain (#7208). Source : `GET /v1/cabinet/lab-work-orders/today`.
class TodayLabWorkOrder extends Equatable {
  final String id;
  final String patientId;
  final String patientDisplayName;
  final String appointmentId;
  final String appointmentStartsAt;
  final String? toothFdi;
  final String? workNature;
  final String labName;
  final String status;
  final String? shippedAt;
  final String? receivedAt;

  const TodayLabWorkOrder({
    required this.id,
    required this.patientId,
    required this.patientDisplayName,
    required this.appointmentId,
    required this.appointmentStartsAt,
    this.toothFdi,
    this.workNature,
    required this.labName,
    required this.status,
    this.shippedAt,
    this.receivedAt,
  });

  @override
  List<Object?> get props => [id, status, shippedAt, receivedAt];
}

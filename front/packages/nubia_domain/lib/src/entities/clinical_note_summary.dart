import 'package:equatable/equatable.dart';

class ClinicalNoteSummary extends Equatable {
  final String id;
  final DateTime timestamp;
  final String patientInitials;
  final String status;

  const ClinicalNoteSummary({
    required this.id,
    required this.timestamp,
    required this.patientInitials,
    required this.status,
  });

  @override
  List<Object?> get props => [id, timestamp, patientInitials, status];
}

import 'package:equatable/equatable.dart';

/// Motif de RDV paramétrable par cabinet (#4084/#4085).
/// Source : `GET /v1/cabinet/appointment-motifs`.
class AppointmentMotif extends Equatable {
  final String id;
  final String label;
  final int? defaultDurationMinutes;

  const AppointmentMotif({
    required this.id,
    required this.label,
    this.defaultDurationMinutes,
  });

  @override
  List<Object?> get props => [id];
}

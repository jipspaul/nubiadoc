import 'package:equatable/equatable.dart';

class TreatmentPhase extends Equatable {
  final String id;
  final int position;
  final String title;
  final String status;

  const TreatmentPhase({
    required this.id,
    required this.position,
    required this.title,
    required this.status,
  });

  @override
  List<Object?> get props => [id, position, title, status];
}

class TreatmentPlan extends Equatable {
  final String id;
  final String title;
  final String status;
  final DateTime createdAt;
  final List<TreatmentPhase> phases;

  const TreatmentPlan({
    required this.id,
    required this.title,
    required this.status,
    required this.createdAt,
    required this.phases,
  });

  @override
  List<Object?> get props => [id, title, status, createdAt, phases];
}

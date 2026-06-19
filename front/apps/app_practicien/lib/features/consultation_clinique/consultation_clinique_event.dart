import 'package:equatable/equatable.dart';

abstract class ConsultationCliniqueEvent extends Equatable {
  const ConsultationCliniqueEvent();
}

class ConsultationCliniqueLoadRequested extends ConsultationCliniqueEvent {
  const ConsultationCliniqueLoadRequested(this.consultationId);
  final String consultationId;

  @override
  List<Object?> get props => [consultationId];
}

class ConsultationCliniqueActAdded extends ConsultationCliniqueEvent {
  const ConsultationCliniqueActAdded({
    required this.ccamCode,
    required this.label,
    this.tooth,
    this.amountCents,
  });
  final String ccamCode;
  final String label;
  final String? tooth;
  final int? amountCents;

  @override
  List<Object?> get props => [ccamCode, label, tooth, amountCents];
}

class ConsultationCliniqueCompleted extends ConsultationCliniqueEvent {
  const ConsultationCliniqueCompleted();

  @override
  List<Object?> get props => [];
}

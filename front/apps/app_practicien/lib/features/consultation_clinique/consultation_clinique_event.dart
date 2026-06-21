import 'package:equatable/equatable.dart';

abstract class ConsultationCliniqueEvent extends Equatable {
  const ConsultationCliniqueEvent();

  @override
  List<Object?> get props => [];
}

class ConsultationCliniqueLoadRequested extends ConsultationCliniqueEvent {
  final String consultationId;
  const ConsultationCliniqueLoadRequested(this.consultationId);

  @override
  List<Object?> get props => [consultationId];
}

class ConsultationCliniqueActAddRequested extends ConsultationCliniqueEvent {
  final String ccamCode;
  final String label;
  final String? tooth;
  final int? amountCents;
  final bool included;

  const ConsultationCliniqueActAddRequested({
    required this.ccamCode,
    required this.label,
    this.tooth,
    this.amountCents,
    this.included = false,
  });

  @override
  List<Object?> get props => [ccamCode, label, tooth, amountCents, included];
}

class ConsultationCliniqueCompleteRequested extends ConsultationCliniqueEvent {
  const ConsultationCliniqueCompleteRequested();
}

class ConsultationHistoriqueRequested extends ConsultationCliniqueEvent {
  const ConsultationHistoriqueRequested();
}

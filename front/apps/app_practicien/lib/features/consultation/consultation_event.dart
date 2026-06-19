import 'package:equatable/equatable.dart';

abstract class ConsultationEvent extends Equatable {
  const ConsultationEvent();

  @override
  List<Object?> get props => [];
}

class ConsultationLoadRequested extends ConsultationEvent {
  final String consultationId;
  const ConsultationLoadRequested(this.consultationId);

  @override
  List<Object?> get props => [consultationId];
}

class ConsultationActAddRequested extends ConsultationEvent {
  final String consultationId;
  final String ccamCode;
  final String label;
  final String? tooth;
  final int? amountCents;
  final bool included;

  const ConsultationActAddRequested({
    required this.consultationId,
    required this.ccamCode,
    required this.label,
    this.tooth,
    this.amountCents,
    this.included = false,
  });

  @override
  List<Object?> get props =>
      [consultationId, ccamCode, label, tooth, amountCents, included];
}

class ConsultationActRemoveRequested extends ConsultationEvent {
  final String consultationId;
  final String actId;

  const ConsultationActRemoveRequested({
    required this.consultationId,
    required this.actId,
  });

  @override
  List<Object?> get props => [consultationId, actId];
}

class ConsultationCompleteRequested extends ConsultationEvent {
  final String consultationId;
  const ConsultationCompleteRequested(this.consultationId);

  @override
  List<Object?> get props => [consultationId];
}

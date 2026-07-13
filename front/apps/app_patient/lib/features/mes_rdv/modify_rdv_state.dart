import 'package:equatable/equatable.dart';
import 'package:nubia_domain/nubia_domain.dart';

abstract class ModifyRdvState extends Equatable {
  const ModifyRdvState();

  @override
  List<Object?> get props => [];
}

class ModifyRdvInitial extends ModifyRdvState {
  const ModifyRdvInitial();
}

class ModifyRdvLoading extends ModifyRdvState {
  const ModifyRdvLoading();
}

class ModifyRdvLoaded extends ModifyRdvState {
  final Appointment appointment;
  final List<Slot> slots;
  final Slot? selectedSlot;
  final bool submitting;
  final String? error;

  const ModifyRdvLoaded({
    required this.appointment,
    required this.slots,
    this.selectedSlot,
    this.submitting = false,
    this.error,
  });

  ModifyRdvLoaded copyWith({
    Slot? selectedSlot,
    bool? submitting,
    String? error,
    bool clearError = false,
  }) => ModifyRdvLoaded(
    appointment: appointment,
    slots: slots,
    selectedSlot: selectedSlot ?? this.selectedSlot,
    submitting: submitting ?? this.submitting,
    error: clearError ? null : (error ?? this.error),
  );

  @override
  List<Object?> get props => [
    appointment,
    slots,
    selectedSlot,
    submitting,
    error,
  ];
}

class ModifyRdvSuccess extends ModifyRdvState {
  final Appointment appointment;
  const ModifyRdvSuccess(this.appointment);

  @override
  List<Object?> get props => [appointment];
}

class ModifyRdvError extends ModifyRdvState {
  final String message;
  const ModifyRdvError(this.message);

  @override
  List<Object?> get props => [message];
}

import 'package:equatable/equatable.dart';
import 'package:nubia_domain/nubia_domain.dart';

abstract class ModifyRdvEvent extends Equatable {
  const ModifyRdvEvent();

  @override
  List<Object?> get props => [];
}

class ModifyRdvLoadRequested extends ModifyRdvEvent {
  final String appointmentId;
  const ModifyRdvLoadRequested(this.appointmentId);

  @override
  List<Object?> get props => [appointmentId];
}

class ModifyRdvSlotSelected extends ModifyRdvEvent {
  final Slot slot;
  const ModifyRdvSlotSelected(this.slot);

  @override
  List<Object?> get props => [slot];
}

class ModifyRdvConfirmRequested extends ModifyRdvEvent {
  const ModifyRdvConfirmRequested();
}

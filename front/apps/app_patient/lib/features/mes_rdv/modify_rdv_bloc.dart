import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'modify_rdv_event.dart';
import 'modify_rdv_state.dart';

class ModifyRdvBloc extends Bloc<ModifyRdvEvent, ModifyRdvState>
    with SafeEmitMixin<ModifyRdvState> {
  final GetAppointmentByIdUseCase _getAppointment;
  final SearchSlotsUseCase _searchSlots;
  final ModifyAppointmentUseCase _modifyAppointment;

  ModifyRdvBloc({
    required GetAppointmentByIdUseCase getAppointment,
    required SearchSlotsUseCase searchSlots,
    required ModifyAppointmentUseCase modifyAppointment,
  }) : _getAppointment = getAppointment,
       _searchSlots = searchSlots,
       _modifyAppointment = modifyAppointment,
       super(const ModifyRdvInitial()) {
    on<ModifyRdvLoadRequested>(_onLoad, transformer: restartable());
    on<ModifyRdvSlotSelected>(_onSlotSelected);
    on<ModifyRdvConfirmRequested>(_onConfirm, transformer: droppable());
  }

  Future<void> _onLoad(
    ModifyRdvLoadRequested event,
    Emitter<ModifyRdvState> emit,
  ) async {
    emit(const ModifyRdvLoading());
    try {
      final appointmentResult = await _getAppointment(event.appointmentId);
      if (appointmentResult.isLeft()) {
        safeEmit(
          ModifyRdvError(appointmentResult.fold((f) => f.message, (_) => '')),
        );
        return;
      }
      final appointment = appointmentResult.getOrElse(
        () => throw StateError('unreachable'),
      );
      if (appointment.practitionerId.isEmpty) {
        safeEmit(
          const ModifyRdvError(
            'Impossible de proposer de nouveaux créneaux pour ce praticien.',
          ),
        );
        return;
      }
      final slotsResult = await _searchSlots(
        providerId: appointment.practitionerId,
      );
      slotsResult.fold(
        (failure) => safeEmit(ModifyRdvError(failure.message)),
        (slots) =>
            safeEmit(ModifyRdvLoaded(appointment: appointment, slots: slots)),
      );
    } catch (_) {
      safeEmit(const ModifyRdvError('Erreur de chargement.'));
    }
  }

  void _onSlotSelected(
    ModifyRdvSlotSelected event,
    Emitter<ModifyRdvState> emit,
  ) {
    final current = state;
    if (current is! ModifyRdvLoaded) return;
    if (!event.slot.isAvailable) return;
    emit(current.copyWith(selectedSlot: event.slot, clearError: true));
  }

  Future<void> _onConfirm(
    ModifyRdvConfirmRequested event,
    Emitter<ModifyRdvState> emit,
  ) async {
    final current = state;
    if (current is! ModifyRdvLoaded) return;
    final slot = current.selectedSlot;
    if (slot == null) return;

    emit(current.copyWith(submitting: true, clearError: true));
    try {
      final result = await _modifyAppointment(
        id: current.appointment.id,
        newStartsAt: slot.startsAt,
      );
      result.fold(
        (failure) => safeEmit(
          current.copyWith(submitting: false, error: failure.message),
        ),
        (updated) => safeEmit(ModifyRdvSuccess(updated)),
      );
    } catch (_) {
      safeEmit(
        current.copyWith(
          submitting: false,
          error: 'Erreur lors de la modification du rendez-vous.',
        ),
      );
    }
  }
}

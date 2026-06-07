import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';
import 'package:nubia_patient/domain/usecases/prescription/create_prescription_use_case.dart';
import 'package:nubia_patient/domain/usecases/prescription/sign_prescription_use_case.dart';
import 'package:nubia_patient/presentation/features/prescription/bloc/prescription_event.dart';
import 'package:nubia_patient/presentation/features/prescription/bloc/prescription_state.dart';

@injectable
class PrescriptionBloc extends Bloc<PrescriptionEvent, PrescriptionState> {
  final CreatePrescriptionUseCase _createPrescription;
  final SignPrescriptionUseCase _signPrescription;

  PrescriptionBloc(
    this._createPrescription,
    this._signPrescription,
  ) : super(const PrescriptionInitial()) {
    on<PrescriptionPatientSelected>(_onPatientSelected);
    on<PrescriptionItemAdded>(_onItemAdded);
    on<PrescriptionItemRemoved>(_onItemRemoved);
    on<PrescriptionCreateRequested>(_onCreateRequested);
    on<PrescriptionSignRequested>(_onSignRequested);
  }

  void _onPatientSelected(
    PrescriptionPatientSelected event,
    Emitter<PrescriptionState> emit,
  ) {
    final current = state;
    if (current is PrescriptionInitial) {
      emit(current.copyWith(
        patientId: event.patientId,
        patientName: event.patientName,
      ));
    }
  }

  void _onItemAdded(
    PrescriptionItemAdded event,
    Emitter<PrescriptionState> emit,
  ) {
    final current = state;
    if (current is PrescriptionInitial) {
      emit(current.copyWith(items: [...current.items, event.item]));
    }
  }

  void _onItemRemoved(
    PrescriptionItemRemoved event,
    Emitter<PrescriptionState> emit,
  ) {
    final current = state;
    if (current is PrescriptionInitial) {
      final updated = [...current.items]..removeAt(event.index);
      emit(current.copyWith(items: updated));
    }
  }

  Future<void> _onCreateRequested(
    PrescriptionCreateRequested event,
    Emitter<PrescriptionState> emit,
  ) async {
    final current = state;
    if (current is! PrescriptionInitial) return;
    if (current.patientId == null || current.items.isEmpty) return;

    emit(const PrescriptionLoading());
    final result = await _createPrescription(
      patientId: current.patientId!,
      items: current.items,
    );
    result.fold(
      (failure) => emit(PrescriptionError(failure.message)),
      (prescription) => emit(PrescriptionLoaded(prescription)),
    );
  }

  Future<void> _onSignRequested(
    PrescriptionSignRequested event,
    Emitter<PrescriptionState> emit,
  ) async {
    final current = state;
    if (current is! PrescriptionLoaded) return;

    final prescription = current.prescription;
    emit(PrescriptionLoading(current: prescription));
    final result = await _signPrescription(prescription.id);
    result.fold(
      (failure) => emit(PrescriptionError(failure.message, current: prescription)),
      (signed) => emit(PrescriptionLoaded(signed)),
    );
  }
}

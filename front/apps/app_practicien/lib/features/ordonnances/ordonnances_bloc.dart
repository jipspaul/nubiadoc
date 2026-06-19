import 'package:bloc/bloc.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'ordonnances_event.dart';
import 'ordonnances_state.dart';

class OrdonnancesBloc extends Bloc<OrdonnancesEvent, OrdonnancesState> {
  final CreatePrescriptionUseCase _create;
  final SignPrescriptionUseCase _sign;

  OrdonnancesBloc({
    required CreatePrescriptionUseCase create,
    required SignPrescriptionUseCase sign,
  })  : _create = create,
        _sign = sign,
        super(const OrdonnancesInitial()) {
    on<OrdonnancesCreateRequested>(_onCreate);
    on<OrdonnancesSignRequested>(_onSign);
  }

  Future<void> _onCreate(
    OrdonnancesCreateRequested event,
    Emitter<OrdonnancesState> emit,
  ) async {
    emit(const OrdonnancesLoading());
    final result = await _create(
      patientId: event.patientId,
      items: event.items,
    );
    result.fold(
      (failure) => emit(OrdonnancesError(failure.message)),
      (prescription) => emit(OrdonnancesCreated(prescription)),
    );
  }

  Future<void> _onSign(
    OrdonnancesSignRequested event,
    Emitter<OrdonnancesState> emit,
  ) async {
    emit(const OrdonnancesLoading());
    final result = await _sign(event.prescriptionId);
    result.fold(
      (failure) => emit(OrdonnancesError(failure.message)),
      (prescription) => emit(OrdonnancesSigned(prescription)),
    );
  }
}

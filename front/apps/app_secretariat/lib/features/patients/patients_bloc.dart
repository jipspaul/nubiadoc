import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'patients_event.dart';
import 'patients_state.dart';

class PatientsBloc extends Bloc<PatientsEvent, PatientsState>
    with SafeEmitMixin<PatientsState> {
  final ListCabinetPatientsUseCase _list;

  PatientsBloc({required ListCabinetPatientsUseCase listPatients})
      : _list = listPatients,
        super(const PatientsInitial()) {
    on<PatientsLoadRequested>(_onLoad);
  }

  Future<void> _onLoad(
    PatientsLoadRequested event,
    Emitter<PatientsState> emit,
  ) async {
    emit(const PatientsLoading());
    try {
      final result = await _list();
      result.fold(
        (failure) => safeEmit(PatientsError(failure.message)),
        (patients) => safeEmit(PatientsLoaded(patients)),
      );
    } catch (_) {
      safeEmit(const PatientsError('Erreur de chargement.'));
    }
  }
}

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'patients_event.dart';
import 'patients_state.dart';

class PatientsBloc extends Bloc<PatientsEvent, PatientsState>
    with SafeEmitMixin<PatientsState> {
  final ListCabinetPatientsUseCase _list;
  final CreateCabinetPatientUseCase _create;

  PatientsBloc({
    required ListCabinetPatientsUseCase listPatients,
    required CreateCabinetPatientUseCase createPatient,
  })  : _list = listPatients,
        _create = createPatient,
        super(const PatientsInitial()) {
    on<PatientsLoadRequested>(_onLoad);
    on<PatientsSearchChanged>(_onSearch);
    on<PatientsCreateRequested>(_onCreate);
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

  Future<void> _onSearch(
    PatientsSearchChanged event,
    Emitter<PatientsState> emit,
  ) async {
    emit(const PatientsLoading());
    try {
      final result = await _list(q: event.query);
      result.fold(
        (failure) => safeEmit(PatientsError(failure.message)),
        (patients) => safeEmit(PatientsLoaded(patients)),
      );
    } catch (_) {
      safeEmit(const PatientsError('Erreur de recherche.'));
    }
  }

  Future<void> _onCreate(
    PatientsCreateRequested event,
    Emitter<PatientsState> emit,
  ) async {
    emit(const PatientsCreating());
    try {
      final result = await _create(
        firstName: event.firstName,
        lastName: event.lastName,
        phone: event.phone,
        birthDate: event.birthDate,
      );
      result.fold(
        (failure) => safeEmit(PatientsCreateError(failure.message)),
        (patient) => safeEmit(PatientsCreateSuccess(patient)),
      );
    } catch (_) {
      safeEmit(const PatientsCreateError('Erreur de création.'));
    }
  }
}

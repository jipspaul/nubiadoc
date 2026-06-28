import 'package:bloc/bloc.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'patients_event.dart';
import 'patients_state.dart';

class PatientsBloc extends Bloc<PatientsEvent, PatientsState>
    with SafeEmitMixin<PatientsState> {
  final ListCabinetPatientsUseCase _list;
  final GetCabinetPatientUseCase _getById;
  final UpdatePatientNotesUseCase _updateNotes;

  PatientsBloc({
    required ListCabinetPatientsUseCase listPatients,
    required GetCabinetPatientUseCase getPatient,
    required UpdatePatientNotesUseCase updateNotes,
  })  : _list = listPatients,
        _getById = getPatient,
        _updateNotes = updateNotes,
        super(const PatientsInitial()) {
    on<PatientsLoadRequested>(_onLoad);
    on<PatientsDetailLoadRequested>(_onDetailLoad);
    on<PatientsNotesUpdateRequested>(_onNotesUpdate);
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

  Future<void> _onDetailLoad(
    PatientsDetailLoadRequested event,
    Emitter<PatientsState> emit,
  ) async {
    emit(const PatientsLoading());
    try {
      final result = await _getById(event.id);
      result.fold(
        (failure) => safeEmit(PatientDetailError(failure.message)),
        (patient) => safeEmit(PatientDetailLoaded(patient)),
      );
    } catch (_) {
      safeEmit(const PatientDetailError('Erreur de chargement.'));
    }
  }

  Future<void> _onNotesUpdate(
    PatientsNotesUpdateRequested event,
    Emitter<PatientsState> emit,
  ) async {
    final current = state;
    if (current is! PatientDetailLoaded) return;
    emit(current.copyWith(notesUpdating: true, clearNotesError: true));
    try {
      final result = await _updateNotes(event.id, event.notes);
      result.fold(
        (failure) => safeEmit(current.copyWith(
          notesUpdating: false,
          notesError: failure.message,
        )),
        (updated) => safeEmit(PatientDetailLoaded(updated)),
      );
    } catch (_) {
      safeEmit(current.copyWith(
          notesUpdating: false, notesError: 'Erreur inattendue.'));
    }
  }
}

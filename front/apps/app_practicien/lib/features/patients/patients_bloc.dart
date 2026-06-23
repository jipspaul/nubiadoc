import 'package:bloc/bloc.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'patients_event.dart';
import 'patients_state.dart';

class PatientsBloc extends Bloc<PatientsEvent, PatientsState> {
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
        (failure) => emit(PatientsError(failure.message)),
        (patients) => emit(PatientsLoaded(patients)),
      );
    } catch (_) {
      emit(const PatientsError('Erreur de chargement.'));
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
        (failure) => emit(PatientDetailError(failure.message)),
        (patient) => emit(PatientDetailLoaded(patient)),
      );
    } catch (_) {
      emit(const PatientDetailError('Erreur de chargement.'));
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
        (failure) => emit(current.copyWith(
          notesUpdating: false,
          notesError: failure.message,
        )),
        (updated) => emit(PatientDetailLoaded(updated)),
      );
    } catch (_) {
      emit(current.copyWith(notesUpdating: false, notesError: 'Erreur inattendue.'));
    }
  }
}

import 'package:flutter_bloc/flutter_bloc.dart';

import '../data/prescription_repository.dart';
import '../models/prescription.dart';
import 'prescription_event.dart';
import 'prescription_state.dart';

class PrescriptionBloc extends Bloc<PrescriptionEvent, PrescriptionState> {
  PrescriptionBloc({required PrescriptionRepository repository})
      : _repository = repository,
        super(const PrescriptionInitial()) {
    on<PrescriptionLoadRequested>(_onLoadRequested);
    on<PrescriptionCreateRequested>(_onCreateRequested);
    on<PrescriptionSignRequested>(_onSignRequested);
  }

  final PrescriptionRepository _repository;

  Future<void> _onLoadRequested(
    PrescriptionLoadRequested event,
    Emitter<PrescriptionState> emit,
  ) async {
    emit(const PrescriptionLoading());
    try {
      final prescriptions = await _repository.fetchAll();
      final patients = await _repository.fetchPatients();
      emit(PrescriptionListLoaded(
        prescriptions: prescriptions,
        patients: patients,
      ));
    } catch (e) {
      emit(PrescriptionError(e.toString()));
    }
  }

  Future<void> _onCreateRequested(
    PrescriptionCreateRequested event,
    Emitter<PrescriptionState> emit,
  ) async {
    final currentPatients = _currentPatients();
    emit(const PrescriptionLoading());
    try {
      final prescription = await _repository.create(
        patientId: event.patientId,
        items: event.items,
      );
      emit(PrescriptionCreated(
        prescription: prescription,
        patients: currentPatients,
      ));
    } catch (e) {
      emit(PrescriptionError(e.toString()));
    }
  }

  Future<void> _onSignRequested(
    PrescriptionSignRequested event,
    Emitter<PrescriptionState> emit,
  ) async {
    final currentPatients = _currentPatients();
    emit(const PrescriptionLoading());
    try {
      final signed = await _repository.sign(event.id);
      emit(PrescriptionSigned(
        prescription: signed,
        patients: currentPatients,
      ));
    } catch (e) {
      emit(PrescriptionError(e.toString()));
    }
  }

  List<PatientSummary> _currentPatients() {
    final s = state;
    if (s is PrescriptionListLoaded) return s.patients;
    if (s is PrescriptionCreated) return s.patients;
    if (s is PrescriptionSigned) return s.patients;
    return [];
  }
}

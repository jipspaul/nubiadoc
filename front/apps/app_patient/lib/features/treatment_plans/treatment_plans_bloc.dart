import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:nubia_domain/nubia_domain.dart';

// ── Liste ─────────────────────────────────────────────────────────────────────

sealed class PatientTreatmentPlansEvent extends Equatable {
  const PatientTreatmentPlansEvent();

  @override
  List<Object?> get props => [];
}

class PatientTreatmentPlansRequested extends PatientTreatmentPlansEvent {
  const PatientTreatmentPlansRequested();
}

sealed class PatientTreatmentPlansState extends Equatable {
  const PatientTreatmentPlansState();

  @override
  List<Object?> get props => [];
}

class PatientTreatmentPlansLoading extends PatientTreatmentPlansState {
  const PatientTreatmentPlansLoading();
}

class PatientTreatmentPlansLoaded extends PatientTreatmentPlansState {
  const PatientTreatmentPlansLoaded(this.plans);

  final List<PatientTreatmentPlan> plans;

  @override
  List<Object?> get props => [plans];
}

class PatientTreatmentPlansError extends PatientTreatmentPlansState {
  const PatientTreatmentPlansError(this.message);

  final String message;

  @override
  List<Object?> get props => [message];
}

/// Liste des plans de traitement du patient (#4261).
class PatientTreatmentPlansBloc
    extends Bloc<PatientTreatmentPlansEvent, PatientTreatmentPlansState> {
  PatientTreatmentPlansBloc({required ListPatientTreatmentPlansUseCase list})
      : _list = list,
        super(const PatientTreatmentPlansLoading()) {
    on<PatientTreatmentPlansRequested>(_onRequested);
  }

  final ListPatientTreatmentPlansUseCase _list;

  Future<void> _onRequested(
    PatientTreatmentPlansRequested event,
    Emitter<PatientTreatmentPlansState> emit,
  ) async {
    emit(const PatientTreatmentPlansLoading());
    final result = await _list();
    result.fold(
      (failure) => emit(PatientTreatmentPlansError(failure.message)),
      (plans) => emit(PatientTreatmentPlansLoaded(plans)),
    );
  }
}

// ── Détail ────────────────────────────────────────────────────────────────────

sealed class PatientTreatmentPlanDetailState extends Equatable {
  const PatientTreatmentPlanDetailState();

  @override
  List<Object?> get props => [];
}

class PatientTreatmentPlanDetailLoading
    extends PatientTreatmentPlanDetailState {
  const PatientTreatmentPlanDetailLoading();
}

class PatientTreatmentPlanDetailLoaded extends PatientTreatmentPlanDetailState {
  const PatientTreatmentPlanDetailLoaded(this.plan);

  final PatientTreatmentPlan plan;

  @override
  List<Object?> get props => [plan];
}

class PatientTreatmentPlanDetailError extends PatientTreatmentPlanDetailState {
  const PatientTreatmentPlanDetailError(this.message);

  final String message;

  @override
  List<Object?> get props => [message];
}

/// Détail d'un plan de traitement (#4261) : phases + actes, chargé par id.
class PatientTreatmentPlanDetailCubit
    extends Cubit<PatientTreatmentPlanDetailState> {
  PatientTreatmentPlanDetailCubit({required GetPatientTreatmentPlanUseCase get})
      : _get = get,
        super(const PatientTreatmentPlanDetailLoading());

  final GetPatientTreatmentPlanUseCase _get;

  Future<void> load(String planId) async {
    emit(const PatientTreatmentPlanDetailLoading());
    final result = await _get(planId);
    result.fold(
      (failure) => emit(PatientTreatmentPlanDetailError(failure.message)),
      (plan) => emit(PatientTreatmentPlanDetailLoaded(plan)),
    );
  }
}

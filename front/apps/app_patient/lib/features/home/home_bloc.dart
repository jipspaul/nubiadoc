import 'package:bloc/bloc.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'home_event.dart';
import 'home_state.dart';

class HomeBloc extends Bloc<HomeEvent, HomeState>
    with SafeEmitMixin<HomeState> {
  final GetDashboardSummaryUseCase _getDashboardSummary;
  final ListPatientTreatmentPlansUseCase _listTreatmentPlans;
  final GetUpcomingAppointmentsUseCase _getUpcomingAppointments;

  HomeBloc({
    required GetDashboardSummaryUseCase getDashboardSummary,
    required ListPatientTreatmentPlansUseCase listTreatmentPlans,
    required GetUpcomingAppointmentsUseCase getUpcomingAppointments,
  })  : _getDashboardSummary = getDashboardSummary,
        _listTreatmentPlans = listTreatmentPlans,
        _getUpcomingAppointments = getUpcomingAppointments,
        super(const HomeInitial()) {
    on<HomeLoadRequested>(_onLoadRequested);
  }

  Future<void> _onLoadRequested(
    HomeLoadRequested event,
    Emitter<HomeState> emit,
  ) async {
    emit(const HomeLoading());
    try {
      final result = await _getDashboardSummary();
      await result.fold(
        (failure) async => safeEmit(HomeError(failure.message)),
        (summary) async => safeEmit(HomeLoaded(
          summary,
          treatmentPlan: await _currentPlan(),
          nextAppointment: await _nextAppointment(),
        )),
      );
    } catch (_) {
      safeEmit(const HomeError('Erreur de chargement.'));
    }
  }

  /// Détail du prochain RDV pour la carte héros (#5198) : le premier RDV à
  /// venir (l'API les trie déjà par `starts_at ASC`), ou `null` si l'appel
  /// échoue ou que la liste est vide — la carte héros retombe alors sur son
  /// état par défaut plutôt que de faire échouer tout l'accueil.
  Future<Appointment?> _nextAppointment() async {
    try {
      final result = await _getUpcomingAppointments();
      return result.fold((_) => null, (appointments) {
        return appointments.isEmpty ? null : appointments.first;
      });
    } catch (_) {
      return null;
    }
  }

  /// Plan de traitement à afficher dans la carte « Mon suivi » : le premier
  /// plan en cours (ni terminé, ni en attente de signature d'un devis) qui
  /// porte des données de progression (#5202). Défaillant/vide → `null`,
  /// la carte est alors simplement masquée plutôt que de faire échouer tout
  /// l'accueil.
  Future<PatientTreatmentPlan?> _currentPlan() async {
    try {
      final result = await _listTreatmentPlans();
      return result.fold((_) => null, (plans) {
        for (final plan in plans) {
          if (plan.pendingQuoteId == null &&
              plan.status != 'done' &&
              plan.stepCount != null &&
              plan.stepCount! > 0 &&
              plan.currentPhaseTitle != null) {
            return plan;
          }
        }
        return null;
      });
    } catch (_) {
      return null;
    }
  }
}

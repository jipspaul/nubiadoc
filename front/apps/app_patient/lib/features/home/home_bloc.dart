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
  final ListMyPrescriptionsUseCase _listPrescriptions;
  final GetDocumentsUseCase _getDocuments;
  final GetMyPharmacyUseCase _getMyPharmacy;
  final ListDependentsUseCase _listDependents;

  HomeBloc({
    required GetDashboardSummaryUseCase getDashboardSummary,
    required ListPatientTreatmentPlansUseCase listTreatmentPlans,
    required GetUpcomingAppointmentsUseCase getUpcomingAppointments,
    required ListMyPrescriptionsUseCase listPrescriptions,
    required GetDocumentsUseCase getDocuments,
    required GetMyPharmacyUseCase getMyPharmacy,
    required ListDependentsUseCase listDependents,
  })  : _getDashboardSummary = getDashboardSummary,
        _listTreatmentPlans = listTreatmentPlans,
        _getUpcomingAppointments = getUpcomingAppointments,
        _listPrescriptions = listPrescriptions,
        _getDocuments = getDocuments,
        _getMyPharmacy = getMyPharmacy,
        _listDependents = listDependents,
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
          activePrescriptionsCount: await _activePrescriptionsCount(),
          documentsCount: await _documentsCount(),
          pharmacy: await _pharmacy(),
          dependentsCount: await _dependentsCount(),
        )),
      );
    } catch (_) {
      safeEmit(const HomeError('Erreur de chargement.'));
    }
  }

  /// Sous-titre d'état de la tuile « Mes ordonnances » (#6963) : nombre
  /// d'ordonnances non brouillon (signées/envoyées). `null` si l'appel
  /// échoue — le sous-titre est alors omis plutôt que d'afficher une
  /// valeur d'exemple (#6215).
  Future<int?> _activePrescriptionsCount() async {
    try {
      final result = await _listPrescriptions();
      return result.fold(
        (_) => null,
        (prescriptions) => prescriptions
            .where((p) => p.status != PrescriptionStatus.draft)
            .length,
      );
    } catch (_) {
      return null;
    }
  }

  /// Sous-titre d'état de la tuile « Mes documents » (#6963).
  Future<int?> _documentsCount() async {
    try {
      final result = await _getDocuments();
      return result.fold((_) => null, (documents) => documents.length);
    } catch (_) {
      return null;
    }
  }

  /// Sous-titre d'état de la tuile « Ma pharmacie » (#6963) : `null` si
  /// aucune pharmacie déclarée ou si l'appel échoue.
  Future<Pharmacy?> _pharmacy() async {
    try {
      final result = await _getMyPharmacy();
      return result.fold((_) => null, (pharmacy) => pharmacy);
    } catch (_) {
      return null;
    }
  }

  /// Sous-titre d'état de la tuile « Mes proches » (#6963).
  Future<int?> _dependentsCount() async {
    try {
      final result = await _listDependents();
      return result.fold((_) => null, (dependents) => dependents.length);
    } catch (_) {
      return null;
    }
  }

  /// Détail du prochain RDV pour la carte héros (#5198) : le premier RDV
  /// dont `startsAt` est encore à venir (l'API les trie par `starts_at ASC`,
  /// mais `filter=upcoming` inclut aussi, dans une fenêtre glissante de 1
  /// jour, les RDV `checked_in`/`in_progress` déjà commencés — #6287, sans
  /// ce filtre un tel RDV passé masquait le vrai RDV du jour). `null` si
  /// l'appel échoue ou que la liste est vide — la carte héros retombe alors
  /// sur son état par défaut plutôt que de faire échouer tout l'accueil.
  /// Aucun RDV à venir : on retombe sur le premier de la liste (RDV en cours
  /// resté seul), plutôt que de masquer la carte sans raison.
  Future<Appointment?> _nextAppointment() async {
    try {
      final result = await _getUpcomingAppointments();
      return result.fold((_) => null, (appointments) {
        if (appointments.isEmpty) return null;
        final now = DateTime.now();
        for (final appointment in appointments) {
          if (appointment.startsAt.isAfter(now)) return appointment;
        }
        return appointments.first;
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

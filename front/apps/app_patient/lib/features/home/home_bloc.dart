import 'dart:developer' as developer;

import 'package:bloc/bloc.dart';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'home_event.dart';
import 'home_state.dart';

class HomeBloc extends Bloc<HomeEvent, HomeState> {
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
    // #6765 : un second `HomeLoadRequested` reçu pendant qu'un premier est
    // encore en vol (double dispatch, tap sur « Réessayer » avant la fin du
    // chargement précédent) faisait courir deux `_onLoadRequested` en
    // parallèle (comportement par défaut de bloc) — la dernière émission à
    // se *terminer* gagnait, pas la dernière *déclenchée* : si l'agrégat
    // « Mon suivi » du premier appel échouait sur un aléa réseau et finissait
    // après le second (pourtant réussi), son `null` écrasait silencieusement
    // le bon résultat. `restartable()` annule le traitement de l'évènement
    // précédent dès qu'un nouveau arrive — mais seules les émissions faites
    // via l'`emit` fourni par le handler (et non `safeEmit`, qui court-
    // circuite cette annulation en écrivant directement sur le bloc)
    // respectent cette annulation, d'où son usage exclusif ci-dessous.
    on<HomeLoadRequested>(_onLoadRequested, transformer: restartable());
  }

  Future<void> _onLoadRequested(
    HomeLoadRequested event,
    Emitter<HomeState> emit,
  ) async {
    emit(const HomeLoading());
    try {
      final result = await _getDashboardSummary();
      await result.fold(
        (failure) async => emit(HomeError(failure.message)),
        (summary) async {
          // Agrégats secondaires lancés en parallèle (#8279) : enchaînés un
          // par un sous `await`, ils gardaient l'accueil en `HomeLoading`
          // pendant la somme de leurs latences plutôt que la plus longue.
          final results = await Future.wait([
            _currentPlan(),
            _nextAppointment(),
            _activePrescriptionsCount(),
            _documentsCount(),
            _pharmacy(),
            _dependentsCount(),
          ]);
          emit(HomeLoaded(
            summary,
            treatmentPlan: results[0] as PatientTreatmentPlan?,
            nextAppointment: results[1] as Appointment?,
            activePrescriptionsCount: results[2] as int?,
            documentsCount: results[3] as int?,
            pharmacy: results[4] as Pharmacy?,
            dependentsCount: results[5] as int?,
          ));
        },
      );
    } catch (_) {
      emit(const HomeError('Erreur de chargement.'));
    }
  }

  /// Sous-titre d'état de la tuile « Mes ordonnances » (#6963) : nombre
  /// d'ordonnances non brouillon (signées/envoyées), déjà filtrées côté API
  /// (#8279) — lu à coût borné (une page) plutôt que paginé jusqu'à
  /// épuisement pour n'en garder que la longueur. `null` si l'appel échoue
  /// — le sous-titre est alors omis plutôt que d'afficher une valeur
  /// d'exemple (#6215).
  Future<int?> _activePrescriptionsCount() async {
    try {
      final result = await _listPrescriptions.count();
      return result.fold((_) => null, (total) => total);
    } catch (_) {
      return null;
    }
  }

  /// Sous-titre d'état de la tuile « Mes documents » (#6963), lu à coût
  /// borné (une page) plutôt que paginé jusqu'à épuisement pour n'en garder
  /// que la longueur (#8279).
  Future<int?> _documentsCount() async {
    try {
      final result = await _getDocuments.count();
      return result.fold((_) => null, (total) => total);
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
      return result.fold((failure) {
        // #6765 : cette branche rendait `null` en silence — la section
        // « Mon suivi » disparaissait sans aucune trace exploitable.
        developer.log(
          'Mon suivi masqué : échec du chargement des plans de traitement.',
          name: 'HomeBloc',
          error: failure.message,
        );
        return null;
      }, (plans) {
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
    } catch (e, stackTrace) {
      // Même raison que ci-dessus : un plan indécodable parmi les autres ne
      // doit pas faire disparaître la section sans laisser de trace.
      developer.log(
        'Mon suivi masqué : exception pendant le chargement des plans de '
        'traitement.',
        name: 'HomeBloc',
        error: e,
        stackTrace: stackTrace,
      );
      return null;
    }
  }
}

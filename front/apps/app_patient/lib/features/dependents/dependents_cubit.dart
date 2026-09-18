import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_domain/nubia_domain.dart';

sealed class DependentsState extends Equatable {
  const DependentsState();
  @override
  List<Object?> get props => [];
}

final class DependentsLoading extends DependentsState {
  const DependentsLoading();
}

final class DependentsLoaded extends DependentsState {
  final List<Dependent> dependents;

  /// Demandes ENVOYÉES par le titulaire, tous statuts (envoyée / acceptée /
  /// refusée / expirée, y compris un accès accepté puis retiré) — un accès
  /// accordé doit rester visible et révocable depuis « Mes proches » (#7008).
  final List<AccessRequest> sentAccessRequests;

  /// Demandes REÇUES par le compte connecté : à décider (`envoyee`) ou accès
  /// qu'il a accordé et peut retirer (`acceptee` non révoqué) (#6809).
  final List<AccessRequest> receivedAccessRequests;
  final bool mutating;

  /// Horodatage du prochain RDV par `dependent.id`, absent si aucun RDV à
  /// venir n'est pris pour ce proche (rapproché via `beneficiaryName`, seul
  /// lien disponible entre [Appointment] et [Dependent]).
  final Map<String, DateTime> nextAppointmentByDependentId;

  /// Le titulaire (patient connecté), affiché en tête de liste — carte
  /// « Vous · titulaire » (maquette design-v2, point 7, #5228). `null` si
  /// non chargé (ex. l'appel `GetAccountUseCase` a échoué) : la carte est
  /// alors simplement absente plutôt que de bloquer l'écran.
  final PatientAccount? account;

  const DependentsLoaded(
    this.dependents, {
    this.sentAccessRequests = const [],
    this.receivedAccessRequests = const [],
    this.mutating = false,
    this.nextAppointmentByDependentId = const {},
    this.account,
  });

  /// Demandes envoyées encore sans réponse (sous-titre « n demandes en
  /// attente », Relancer / Annuler).
  List<AccessRequest> get pendingAccessRequests =>
      sentAccessRequests.where((r) => r.isPending).toList();

  /// Demandes reçues en attente de MA décision (écran « Décider »).
  List<AccessRequest> get incomingPendingRequests =>
      receivedAccessRequests.where((r) => r.isPending).toList();

  bool get hasPendingAccessRequest => pendingAccessRequests.isNotEmpty;

  DependentsLoaded copyWith({bool? mutating}) => DependentsLoaded(
        dependents,
        sentAccessRequests: sentAccessRequests,
        receivedAccessRequests: receivedAccessRequests,
        mutating: mutating ?? this.mutating,
        nextAppointmentByDependentId: nextAppointmentByDependentId,
        account: account,
      );

  @override
  List<Object?> get props => [
        dependents,
        sentAccessRequests,
        receivedAccessRequests,
        mutating,
        nextAppointmentByDependentId,
        account,
      ];
}

final class DependentsError extends DependentsState {
  final String message;
  const DependentsError(this.message);
  @override
  List<Object?> get props => [message];
}

class DependentsCubit extends Cubit<DependentsState>
    with SafeEmitMixin<DependentsState> {
  DependentsCubit({
    required ListDependentsUseCase list,
    required ListAccessRequestsUseCase listAccessRequests,
    required GetUpcomingAppointmentsUseCase getUpcomingAppointments,
    required GetAccountUseCase getAccount,
    required AddDependentUseCase add,
    required DeleteDependentUseCase remove,
    required SendAccessRequestUseCase sendAccessRequest,
    required ResendAccessRequestUseCase resendAccessRequest,
    required CancelAccessRequestUseCase cancelAccessRequest,
    required RevokeAccessUseCase revokeAccess,
  })  : _list = list,
        _listAccessRequests = listAccessRequests,
        _getUpcomingAppointments = getUpcomingAppointments,
        _getAccount = getAccount,
        _add = add,
        _remove = remove,
        _sendAccessRequest = sendAccessRequest,
        _resendAccessRequest = resendAccessRequest,
        _cancelAccessRequest = cancelAccessRequest,
        _revokeAccess = revokeAccess,
        super(const DependentsLoading());

  final ListDependentsUseCase _list;
  final ListAccessRequestsUseCase _listAccessRequests;
  final GetUpcomingAppointmentsUseCase _getUpcomingAppointments;
  final GetAccountUseCase _getAccount;
  final AddDependentUseCase _add;
  final DeleteDependentUseCase _remove;
  final SendAccessRequestUseCase _sendAccessRequest;
  final ResendAccessRequestUseCase _resendAccessRequest;
  final CancelAccessRequestUseCase _cancelAccessRequest;
  final RevokeAccessUseCase _revokeAccess;

  Future<void> load() async {
    emit(const DependentsLoading());
    final result = await _list();
    await result.fold(
      (f) async => safeEmit(DependentsError(f.message)),
      (d) async {
        final requestsResult = await _listAccessRequests();
        final requests = requestsResult.fold(
          (_) => const <AccessRequest>[],
          (requests) => requests,
        );
        // #7008 : plus de filtre sur `envoyee` — un accès accepté (ou retiré)
        // reste affiché, sinon le titulaire ne sait pas qui a accès à quoi.
        final sent = requests.where((r) => !r.isReceived).toList();
        final received = requests
            .where((r) => r.isReceived && (r.isPending || r.isActiveAccess))
            .toList();
        final upcomingResult = await _getUpcomingAppointments();
        final upcoming =
            upcomingResult.fold((_) => const <Appointment>[], (a) => a);
        final nextAppointments = <String, DateTime>{};
        for (final dependent in d) {
          final matches = upcoming.where((a) =>
              !a.beneficiaryIsSelf &&
              a.beneficiaryName == dependent.displayName &&
              a.status != AppointmentStatus.cancelled);
          if (matches.isEmpty) continue;
          nextAppointments[dependent.id] = matches
              .map((a) => a.startsAt)
              .reduce((a, b) => a.isBefore(b) ? a : b);
        }
        final accountResult = await _getAccount();
        final account = accountResult.fold((_) => null, (a) => a);
        safeEmit(DependentsLoaded(
          d,
          sentAccessRequests: sent,
          receivedAccessRequests: received,
          nextAppointmentByDependentId: nextAppointments,
          account: account,
        ));
      },
    );
  }

  void _emitMutating() {
    final current = state;
    if (current is DependentsLoaded) {
      emit(current.copyWith(mutating: true));
    }
  }

  Future<void> _reloadAfter(Future<Either<Failure, dynamic>> action) async {
    final result = await action;
    await result.fold(
      (f) async {
        safeEmit(DependentsError(f.message));
        await load();
      },
      (_) async => load(),
    );
  }

  /// Rattachement DIRECT d'un enfant mineur (compte géré). Un proche adulte
  /// ne passe jamais par ici : cf. [sendAccessRequest] (#7009).
  Future<void> add({
    required String firstName,
    required String lastName,
    DateTime? birthDate,
    required DependentRelationship relationship,
  }) async {
    _emitMutating();
    await _reloadAfter(_add(
      firstName: firstName,
      lastName: lastName,
      birthDate: birthDate,
      relationship: relationship,
    ));
  }

  /// Invitation d'un proche ADULTE (conjoint/autre) : crée une demande en
  /// attente que l'intéressé devra accepter — aucun accès avant (#7009).
  /// [scope] : périmètre proposé (bascules « Ce que vous pourrez faire »).
  Future<void> sendAccessRequest({
    required String firstName,
    required String lastName,
    required DependentRelationship relationship,
    required String email,
    required Set<AccessRight> scope,
  }) async {
    _emitMutating();
    await _reloadAfter(_sendAccessRequest(
      firstName: firstName,
      lastName: lastName,
      relationship: relationship,
      channel: AccessRequestChannel.email,
      scope: scope,
      email: email,
    ));
  }

  Future<void> remove(String id) async {
    _emitMutating();
    await _reloadAfter(_remove(id));
  }

  Future<void> resend(String requestId) async {
    _emitMutating();
    await _reloadAfter(_resendAccessRequest(requestId));
  }

  Future<void> cancel(String requestId) async {
    _emitMutating();
    await _reloadAfter(_cancelAccessRequest(requestId));
  }

  /// Retire un accès accordé — par le titulaire qui l'a obtenu (demande
  /// envoyée acceptée) ou par l'invité qui l'a accordé (demande reçue
  /// acceptée) : révocation symétrique (#7004).
  Future<void> revokeAccess(String requestId) async {
    _emitMutating();
    await _reloadAfter(_revokeAccess(requestId));
  }
}

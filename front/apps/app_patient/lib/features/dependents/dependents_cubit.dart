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
  final List<AccessRequest> pendingAccessRequests;
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
    this.pendingAccessRequests = const [],
    this.mutating = false,
    this.nextAppointmentByDependentId = const {},
    this.account,
  });

  bool get hasPendingAccessRequest => pendingAccessRequests.isNotEmpty;

  @override
  List<Object?> get props => [
        dependents,
        pendingAccessRequests,
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
    required ResendAccessRequestUseCase resendAccessRequest,
    required CancelAccessRequestUseCase cancelAccessRequest,
  })  : _list = list,
        _listAccessRequests = listAccessRequests,
        _getUpcomingAppointments = getUpcomingAppointments,
        _getAccount = getAccount,
        _add = add,
        _remove = remove,
        _resendAccessRequest = resendAccessRequest,
        _cancelAccessRequest = cancelAccessRequest,
        super(const DependentsLoading());

  final ListDependentsUseCase _list;
  final ListAccessRequestsUseCase _listAccessRequests;
  final GetUpcomingAppointmentsUseCase _getUpcomingAppointments;
  final GetAccountUseCase _getAccount;
  final AddDependentUseCase _add;
  final DeleteDependentUseCase _remove;
  final ResendAccessRequestUseCase _resendAccessRequest;
  final CancelAccessRequestUseCase _cancelAccessRequest;

  Future<void> load() async {
    emit(const DependentsLoading());
    final result = await _list();
    await result.fold(
      (f) async => safeEmit(DependentsError(f.message)),
      (d) async {
        final requestsResult = await _listAccessRequests();
        final pending = requestsResult.fold(
          (_) => const <AccessRequest>[],
          (requests) => requests
              .where((r) => r.status == AccessRequestStatus.envoyee)
              .toList(),
        );
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
          pendingAccessRequests: pending,
          nextAppointmentByDependentId: nextAppointments,
          account: account,
        ));
      },
    );
  }

  Future<void> add({
    required String firstName,
    required String lastName,
    DateTime? birthDate,
    required DependentRelationship relationship,
  }) async {
    final current = state;
    if (current is DependentsLoaded) {
      emit(DependentsLoaded(
        current.dependents,
        pendingAccessRequests: current.pendingAccessRequests,
        mutating: true,
        account: current.account,
      ));
    }
    final result = await _add(
      firstName: firstName,
      lastName: lastName,
      birthDate: birthDate,
      relationship: relationship,
    );
    await result.fold(
      (f) async {
        safeEmit(DependentsError(f.message));
        await load();
      },
      (_) async => load(),
    );
  }

  Future<void> remove(String id) async {
    final current = state;
    if (current is DependentsLoaded) {
      emit(DependentsLoaded(
        current.dependents,
        pendingAccessRequests: current.pendingAccessRequests,
        mutating: true,
        account: current.account,
      ));
    }
    final result = await _remove(id);
    await result.fold(
      (f) async {
        safeEmit(DependentsError(f.message));
        await load();
      },
      (_) async => load(),
    );
  }

  Future<void> resend(String requestId) async {
    final current = state;
    if (current is DependentsLoaded) {
      emit(DependentsLoaded(
        current.dependents,
        pendingAccessRequests: current.pendingAccessRequests,
        mutating: true,
        account: current.account,
      ));
    }
    final result = await _resendAccessRequest(requestId);
    await result.fold(
      (f) async {
        safeEmit(DependentsError(f.message));
        await load();
      },
      (_) async => load(),
    );
  }

  Future<void> cancel(String requestId) async {
    final current = state;
    if (current is DependentsLoaded) {
      emit(DependentsLoaded(
        current.dependents,
        pendingAccessRequests: current.pendingAccessRequests,
        mutating: true,
        account: current.account,
      ));
    }
    final result = await _cancelAccessRequest(requestId);
    await result.fold(
      (f) async {
        safeEmit(DependentsError(f.message));
        await load();
      },
      (_) async => load(),
    );
  }
}

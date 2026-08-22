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
  final bool hasPendingAccessRequest;
  final bool mutating;

  /// Horodatage du prochain RDV par `dependent.id`, absent si aucun RDV à
  /// venir n'est pris pour ce proche (rapproché via `beneficiaryName`, seul
  /// lien disponible entre [Appointment] et [Dependent]).
  final Map<String, DateTime> nextAppointmentByDependentId;

  const DependentsLoaded(
    this.dependents, {
    this.hasPendingAccessRequest = false,
    this.mutating = false,
    this.nextAppointmentByDependentId = const {},
  });
  @override
  List<Object?> get props => [
        dependents,
        hasPendingAccessRequest,
        mutating,
        nextAppointmentByDependentId,
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
    required AddDependentUseCase add,
    required DeleteDependentUseCase remove,
  })  : _list = list,
        _listAccessRequests = listAccessRequests,
        _getUpcomingAppointments = getUpcomingAppointments,
        _add = add,
        _remove = remove,
        super(const DependentsLoading());

  final ListDependentsUseCase _list;
  final ListAccessRequestsUseCase _listAccessRequests;
  final GetUpcomingAppointmentsUseCase _getUpcomingAppointments;
  final AddDependentUseCase _add;
  final DeleteDependentUseCase _remove;

  Future<void> load() async {
    emit(const DependentsLoading());
    final result = await _list();
    await result.fold(
      (f) async => safeEmit(DependentsError(f.message)),
      (d) async {
        final requestsResult = await _listAccessRequests();
        final hasPending = requestsResult.fold(
          (_) => false,
          (requests) => requests
              .any((r) => r.status == AccessRequestStatus.envoyee),
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
        safeEmit(DependentsLoaded(
          d,
          hasPendingAccessRequest: hasPending,
          nextAppointmentByDependentId: nextAppointments,
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
        hasPendingAccessRequest: current.hasPendingAccessRequest,
        mutating: true,
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
        hasPendingAccessRequest: current.hasPendingAccessRequest,
        mutating: true,
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
}

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
  final bool mutating;
  const DependentsLoaded(this.dependents, {this.mutating = false});
  @override
  List<Object?> get props => [dependents, mutating];
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
    required AddDependentUseCase add,
    required DeleteDependentUseCase remove,
  })  : _list = list,
        _add = add,
        _remove = remove,
        super(const DependentsLoading());

  final ListDependentsUseCase _list;
  final AddDependentUseCase _add;
  final DeleteDependentUseCase _remove;

  Future<void> load() async {
    emit(const DependentsLoading());
    final result = await _list();
    result.fold(
      (f) => safeEmit(DependentsError(f.message)),
      (d) => safeEmit(DependentsLoaded(d)),
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
      emit(DependentsLoaded(current.dependents, mutating: true));
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
      emit(DependentsLoaded(current.dependents, mutating: true));
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

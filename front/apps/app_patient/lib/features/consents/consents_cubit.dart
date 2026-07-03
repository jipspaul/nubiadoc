import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_domain/nubia_domain.dart';

sealed class ConsentsState extends Equatable {
  const ConsentsState();
  @override
  List<Object?> get props => [];
}

final class ConsentsLoading extends ConsentsState {
  const ConsentsLoading();
}

final class ConsentsLoaded extends ConsentsState {
  final List<Consent> consents;

  /// Purpose en cours d'écriture (bascule optimiste désactivée pendant l'appel).
  final String? pending;
  const ConsentsLoaded(this.consents, {this.pending});
  @override
  List<Object?> get props => [consents, pending];
}

final class ConsentsError extends ConsentsState {
  final String message;
  const ConsentsError(this.message);
  @override
  List<Object?> get props => [message];
}

class ConsentsCubit extends Cubit<ConsentsState>
    with SafeEmitMixin<ConsentsState> {
  ConsentsCubit({
    required ListConsentsUseCase list,
    required SetConsentUseCase set,
  })  : _list = list,
        _set = set,
        super(const ConsentsLoading());

  final ListConsentsUseCase _list;
  final SetConsentUseCase _set;

  Future<void> load() async {
    emit(const ConsentsLoading());
    final result = await _list();
    result.fold(
      (f) => safeEmit(ConsentsError(f.message)),
      (c) => safeEmit(ConsentsLoaded(c)),
    );
  }

  Future<void> toggle(String purpose, bool granted) async {
    final current = state;
    if (current is! ConsentsLoaded) return;
    emit(ConsentsLoaded(current.consents, pending: purpose));
    final result = await _set(purpose: purpose, granted: granted);
    await result.fold(
      (f) async {
        safeEmit(ConsentsError(f.message));
        await load();
      },
      (_) async => load(),
    );
  }
}

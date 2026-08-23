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

  /// Message d'échec d'une bascule (#5215) : reste local à la ligne (SnackBar),
  /// ne remplace jamais la liste par un écran d'erreur plein écran.
  final String? toggleError;
  const ConsentsLoaded(this.consents, {this.pending, this.toggleError});
  @override
  List<Object?> get props => [consents, pending, toggleError];
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
      // Échec d'une bascule : erreur locale à la ligne (SnackBar), la liste
      // reste affichée et la bascule revient à son état serveur — jamais de
      // NubiaErrorWidget plein écran pour l'échec d'UN consentement (#5215).
      (f) async => safeEmit(
        ConsentsLoaded(current.consents, toggleError: f.message),
      ),
      (_) async => load(),
    );
  }
}

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_domain/nubia_domain.dart';

sealed class PharmaNotificationPrefsState extends Equatable {
  const PharmaNotificationPrefsState();
  @override
  List<Object?> get props => [];
}

final class PharmaNotificationPrefsLoading
    extends PharmaNotificationPrefsState {
  const PharmaNotificationPrefsLoading();
}

final class PharmaNotificationPrefsLoaded
    extends PharmaNotificationPrefsState {
  final ProNotificationPreferences prefs;
  final bool saving;
  const PharmaNotificationPrefsLoaded(this.prefs, {this.saving = false});
  @override
  List<Object?> get props => [prefs, saving];
}

final class PharmaNotificationPrefsError extends PharmaNotificationPrefsState {
  final String message;
  const PharmaNotificationPrefsError(this.message);
  @override
  List<Object?> get props => [message];
}

class PharmaNotificationPrefsCubit
    extends Cubit<PharmaNotificationPrefsState>
    with SafeEmitMixin<PharmaNotificationPrefsState> {
  PharmaNotificationPrefsCubit({
    required GetProNotificationPreferencesUseCase get,
    required UpdateProNotificationPreferencesUseCase update,
  })  : _get = get,
        _update = update,
        super(const PharmaNotificationPrefsLoading());

  final GetProNotificationPreferencesUseCase _get;
  final UpdateProNotificationPreferencesUseCase _update;

  Future<void> load() async {
    emit(const PharmaNotificationPrefsLoading());
    final result = await _get();
    result.fold(
      (f) => safeEmit(PharmaNotificationPrefsError(f.message)),
      (p) => safeEmit(PharmaNotificationPrefsLoaded(p)),
    );
  }

  /// Applique un changement optimiste et persiste ; rollback sur échec (#6265).
  Future<void> save(ProNotificationPreferences updated) async {
    final current = state;
    if (current is! PharmaNotificationPrefsLoaded) return;
    final previous = current.prefs;
    emit(PharmaNotificationPrefsLoaded(updated, saving: true));
    final result = await _update(updated);
    result.fold(
      (f) {
        safeEmit(PharmaNotificationPrefsError(f.message));
        safeEmit(PharmaNotificationPrefsLoaded(previous));
      },
      (saved) => safeEmit(PharmaNotificationPrefsLoaded(saved)),
    );
  }
}

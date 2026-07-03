import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_domain/nubia_domain.dart';

sealed class NotificationPrefsState extends Equatable {
  const NotificationPrefsState();
  @override
  List<Object?> get props => [];
}

final class NotificationPrefsLoading extends NotificationPrefsState {
  const NotificationPrefsLoading();
}

final class NotificationPrefsLoaded extends NotificationPrefsState {
  final NotificationPreferences prefs;
  final bool saving;
  const NotificationPrefsLoaded(this.prefs, {this.saving = false});
  @override
  List<Object?> get props => [prefs, saving];
}

final class NotificationPrefsError extends NotificationPrefsState {
  final String message;
  const NotificationPrefsError(this.message);
  @override
  List<Object?> get props => [message];
}

class NotificationPrefsCubit extends Cubit<NotificationPrefsState>
    with SafeEmitMixin<NotificationPrefsState> {
  NotificationPrefsCubit({
    required GetNotificationPreferencesUseCase get,
    required UpdateNotificationPreferencesUseCase update,
  })  : _get = get,
        _update = update,
        super(const NotificationPrefsLoading());

  final GetNotificationPreferencesUseCase _get;
  final UpdateNotificationPreferencesUseCase _update;

  Future<void> load() async {
    emit(const NotificationPrefsLoading());
    final result = await _get();
    result.fold(
      (f) => safeEmit(NotificationPrefsError(f.message)),
      (p) => safeEmit(NotificationPrefsLoaded(p)),
    );
  }

  /// Applique un changement optimiste et persiste ; rollback sur échec.
  Future<void> save(NotificationPreferences updated) async {
    final current = state;
    if (current is! NotificationPrefsLoaded) return;
    final previous = current.prefs;
    emit(NotificationPrefsLoaded(updated, saving: true));
    final result = await _update(updated);
    result.fold(
      (f) => safeEmit(NotificationPrefsError(f.message)),
      (_) => safeEmit(NotificationPrefsLoaded(updated)),
    );
    if (result.isLeft()) {
      safeEmit(NotificationPrefsLoaded(previous));
    }
  }
}

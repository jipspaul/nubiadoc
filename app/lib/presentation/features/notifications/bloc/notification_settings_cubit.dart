import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';
import 'package:nubia_patient/domain/repositories/notification_repository.dart';
import 'package:nubia_patient/presentation/features/notifications/bloc/notification_settings_state.dart';

@injectable
class NotificationSettingsCubit extends Cubit<NotificationSettingsState> {
  NotificationSettingsCubit(this._repository)
      : super(const NotificationSettingsInitial());

  final NotificationRepository _repository;

  Future<void> load() async {
    emit(const NotificationSettingsLoading());
    final result = await _repository.getPreferences();
    result.fold(
      (failure) => emit(NotificationSettingsError(failure.message)),
      (prefs) => emit(NotificationSettingsLoaded(prefs)),
    );
  }

  Future<void> toggle({
    bool? appointments,
    bool? documents,
    bool? messages,
    bool? payments,
    bool? prevention,
  }) async {
    final current = state;
    if (current is! NotificationSettingsLoaded) return;

    final updated = current.preferences.copyWith(
      appointments: appointments,
      documents: documents,
      messages: messages,
      payments: payments,
      prevention: prevention,
    );

    // Optimistic update.
    emit(NotificationSettingsLoaded(updated));

    // Best-effort server sync; restore on failure.
    final result = await _repository.updatePreferences(updated);
    result.fold(
      (failure) {
        // Revert to previous state on error.
        emit(current);
      },
      (_) {},
    );
  }
}

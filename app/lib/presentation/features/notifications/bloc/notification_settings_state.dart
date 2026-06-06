import 'package:equatable/equatable.dart';
import 'package:nubia_patient/domain/entities/notification_preferences.dart';

sealed class NotificationSettingsState extends Equatable {
  const NotificationSettingsState();

  @override
  List<Object?> get props => [];
}

final class NotificationSettingsInitial extends NotificationSettingsState {
  const NotificationSettingsInitial();
}

final class NotificationSettingsLoading extends NotificationSettingsState {
  const NotificationSettingsLoading();
}

final class NotificationSettingsLoaded extends NotificationSettingsState {
  final NotificationPreferences preferences;

  const NotificationSettingsLoaded(this.preferences);

  @override
  List<Object?> get props => [preferences];
}

final class NotificationSettingsError extends NotificationSettingsState {
  final String message;

  const NotificationSettingsError(this.message);

  @override
  List<Object?> get props => [message];
}

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:injectable/injectable.dart';
import 'package:nubia_patient/domain/repositories/notification_repository.dart';
import 'package:nubia_patient/presentation/features/notifications/bloc/notification_bloc.dart';
import 'package:nubia_patient/presentation/features/notifications/bloc/notification_event.dart';

/// Initialises Firebase Cloud Messaging and wires push events to
/// [NotificationBloc].
///
/// Call [init] once from [bootstrap] after [configureDependencies].
/// [bloc] is the application-lifetime [NotificationBloc] instance.
@injectable
class FcmService {
  FcmService(this._messaging, this._repository);

  final FirebaseMessaging _messaging;
  final NotificationRepository _repository;

  /// Initialises FCM: requests permission, registers the token, and subscribes
  /// to foreground / background message streams.
  ///
  /// [bloc] must already be created before this is called.
  Future<void> init(NotificationBloc bloc) async {
    // Request opt-in permission (iOS / Android 13+).
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      // User denied — don't register token; the app still works.
      return;
    }

    // Register device token.
    final token = await _messaging.getToken();
    if (token != null) {
      await _repository.registerFcmToken(token);
    }

    // Refresh token when FCM rotates it.
    _messaging.onTokenRefresh.listen((newToken) {
      _repository.registerFcmToken(newToken);
    });

    // Foreground messages.
    FirebaseMessaging.onMessage.listen((message) {
      _dispatchToBloc(bloc, message);
    });

    // Background / terminated — message opened the app.
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      _dispatchToBloc(bloc, message);
    });
  }

  void _dispatchToBloc(NotificationBloc bloc, RemoteMessage message) {
    final title = message.notification?.title ?? '';
    final body = message.notification?.body ?? '';
    final deepLink = message.data['deep_link'] as String?;

    if (title.isNotEmpty || body.isNotEmpty) {
      bloc.add(NotificationReceived(
        title: title,
        body: body,
        deepLink: deepLink,
      ));
    }
  }
}

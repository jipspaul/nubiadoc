import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:nubia_patient/app.dart';
import 'package:nubia_patient/core/di/injection.dart';
import 'package:nubia_patient/core/utils/fcm_service.dart';
import 'package:nubia_patient/presentation/features/notifications/bloc/notification_bloc.dart';
import 'package:nubia_patient/presentation/features/notifications/bloc/notification_event.dart';

Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  await configureDependencies();

  // Initialise FCM and attach it to the app-lifetime NotificationBloc.
  final notificationBloc = getIt<NotificationBloc>()
    ..add(const NotificationsLoadRequested());
  await getIt<FcmService>().init(notificationBloc);

  runApp(NubiaApp(notificationBloc: notificationBloc));
}

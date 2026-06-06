import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:nubia_patient/core/di/injection.dart';
import 'package:nubia_patient/core/router/app_router.dart';
import 'package:nubia_patient/core/router/router_notifier.dart';
import 'package:nubia_patient/core/storage/token_storage.dart';
import 'package:nubia_patient/presentation/features/auth/bloc/auth_bloc.dart';
import 'package:nubia_patient/presentation/features/notifications/bloc/notification_bloc.dart';
import 'package:nubia_patient/presentation/theme/nubia_theme.dart';

class NubiaApp extends StatefulWidget {
  const NubiaApp({super.key, required this.notificationBloc});

  final NotificationBloc notificationBloc;

  @override
  State<NubiaApp> createState() => _NubiaAppState();
}

class _NubiaAppState extends State<NubiaApp> {
  late final AuthBloc _authBloc;
  late final RouterNotifier _routerNotifier;
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _authBloc = getIt<AuthBloc>();
    _routerNotifier = RouterNotifier(getIt<TokenStorage>());
    _routerNotifier.addAuthListener(_authBloc);
    _router = AppRouter.create(_routerNotifier);
  }

  @override
  void dispose() {
    _authBloc.close();
    _routerNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<AuthBloc>.value(value: _authBloc),
        BlocProvider<NotificationBloc>.value(value: widget.notificationBloc),
      ],
      child: MaterialApp.router(
        title: 'Nubia',
        theme: NubiaTheme.light,
        darkTheme: NubiaTheme.dark,
        themeMode: ThemeMode.system,
        routerConfig: _router,
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}

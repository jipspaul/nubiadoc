import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

import 'pro_config.dart';
import 'router/app_router.dart';
import 'session/pro_auth_cubit.dart';

class NubiaProApp extends StatefulWidget {
  const NubiaProApp({super.key});

  @override
  State<NubiaProApp> createState() => _NubiaProAppState();
}

class _NubiaProAppState extends State<NubiaProApp> {
  late final ProAuthCubit _auth;
  late final RouterNotifier _notifier;
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _auth = getIt<ProAuthCubit>();
    _notifier = RouterNotifier(getIt<TokenStorage>());
    _auth.stream.listen((state) {
      if (state is AuthAuthenticated) {
        _notifier.markAuthenticated();
      } else if (state is AuthUnauthenticated) {
        _notifier.markUnauthenticated();
      }
    });
    _auth.restore();
    _router = AppRouter.create(_notifier);
  }

  @override
  void dispose() {
    _auth.close();
    _notifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: _auth,
      child: MaterialApp.router(
        title: ProConfig.appTitle,
        theme: NubiaTheme.light,
        darkTheme: NubiaTheme.dark,
        themeMode: ThemeMode.system,
        routerConfig: _router,
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}

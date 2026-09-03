import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

import 'features/notifications/notification_route_resolver.dart';
import 'infirmiere_config.dart';
import 'router/app_router.dart';
import 'session/infirmiere_auth_cubit.dart';

class NubiaInfirmiereApp extends StatefulWidget {
  const NubiaInfirmiereApp({super.key});

  @override
  State<NubiaInfirmiereApp> createState() => _NubiaInfirmiereAppState();
}

class _NubiaInfirmiereAppState extends State<NubiaInfirmiereApp> {
  late final InfirmiereAuthCubit _auth;
  late final RouterNotifier _notifier;
  late final GoRouter _router;
  late final FcmTapRouter _fcmTapRouter;

  @override
  void initState() {
    super.initState();
    _auth = getIt<InfirmiereAuthCubit>();
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
    _fcmTapRouter = FcmTapRouter(
      _router,
      (message) => NotificationRouteResolver.resolve(
        kind: message.data['kind'] as String?,
        data: message.data,
      ),
    );
    _fcmTapRouter.init();
  }

  @override
  void dispose() {
    _fcmTapRouter.dispose();
    _auth.close();
    _notifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PostHogWidget(
      child: BlocProvider.value(
        value: _auth,
        child: MaterialApp.router(
          title: InfirmiereConfig.appTitle,
          theme: NubiaTheme.light,
          darkTheme: NubiaTheme.dark,
          themeMode: ThemeMode.system,
          routerConfig: _router,
          debugShowCheckedModeBanner: false,
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('fr')],
        ),
      ),
    );
  }
}

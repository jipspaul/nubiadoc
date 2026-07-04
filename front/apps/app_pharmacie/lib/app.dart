import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

import 'pharma_config.dart';
import 'router/app_router.dart';
import 'session/pharma_auth_cubit.dart';

class NubiaPharmaApp extends StatefulWidget {
  const NubiaPharmaApp({super.key});

  @override
  State<NubiaPharmaApp> createState() => _NubiaPharmaAppState();
}

class _NubiaPharmaAppState extends State<NubiaPharmaApp> {
  late final PharmaAuthCubit _auth;
  late final RouterNotifier _notifier;
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _auth = getIt<PharmaAuthCubit>();
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
    // PostHogWidget enveloppe l'arbre pour le session replay (masqué — santé).
    return PostHogWidget(
      child: BlocProvider.value(
        value: _auth,
        child: MaterialApp.router(
          title: PharmaConfig.appTitle,
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

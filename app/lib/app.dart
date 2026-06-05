import 'package:flutter/material.dart';
import 'package:nubia_patient/core/router/app_router.dart';
import 'package:nubia_patient/presentation/theme/nubia_theme.dart';

class NubiaApp extends StatelessWidget {
  const NubiaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Nubia',
      theme: NubiaTheme.light,
      darkTheme: NubiaTheme.dark,
      themeMode: ThemeMode.system,
      routerConfig: AppRouter.router,
      debugShowCheckedModeBanner: false,
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nubia_app_shell/nubia_app_shell.dart';

/// Minimal GoRouter wired with a single '/' route that renders [ProShell].
GoRouter _router({
  required ProConfig config,
  required bool canAccessClinical,
}) {
  return GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (_, __) => ProShell(
          config: config,
          canAccessClinical: canAccessClinical,
          body: const SizedBox.shrink(),
        ),
      ),
      // Stub routes for the nav destinations so go_router doesn't throw.
      GoRoute(path: '/agenda', builder: (_, __) => const SizedBox.shrink()),
      GoRoute(path: '/patients', builder: (_, __) => const SizedBox.shrink()),
      GoRoute(
          path: '/consultation', builder: (_, __) => const SizedBox.shrink()),
    ],
  );
}

const _config = ProConfig(
  homeRoute: '/',
  nav: [
    ProNavDestination(
      icon: Icons.calendar_month_outlined,
      label: 'Agenda',
      route: '/agenda',
    ),
    ProNavDestination(
      icon: Icons.groups_outlined,
      label: 'Patients',
      route: '/patients',
    ),
    ProNavDestination(
      icon: Icons.medical_services_outlined,
      label: 'Consultation',
      route: '/consultation',
      requiresClinical: true,
    ),
  ],
);

void main() {
  testWidgets(
    'shows all 3 destinations when canAccessClinical is true',
    (tester) async {
      tester.view.physicalSize = const Size(900, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(MaterialApp.router(
        routerConfig: _router(config: _config, canAccessClinical: true),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Agenda'), findsOneWidget);
      expect(find.text('Patients'), findsOneWidget);
      expect(find.text('Consultation'), findsOneWidget);
    },
  );

  testWidgets(
    'hides clinical destination when canAccessClinical is false',
    (tester) async {
      tester.view.physicalSize = const Size(900, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(MaterialApp.router(
        routerConfig: _router(config: _config, canAccessClinical: false),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Agenda'), findsOneWidget);
      expect(find.text('Patients'), findsOneWidget);
      expect(find.text('Consultation'), findsNothing);
    },
  );
}

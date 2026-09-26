// Régression #6981 — l'écran « Réessayer » de #6750 (coupure réseau pendant
// AuthCubit.restore(), token pas invalidé) n'était câblé que sur la route
// /splash. Un rechargement web sur une route protégée profonde (ex.
// /mes-rdv) ne construit jamais /splash : AuthRestoreFailed n'avait alors
// aucun effet visible et la route retombait sur le formulaire de login alors
// que la session était intacte. AuthRestoreOverlay (branché dans le
// `builder:` de MaterialApp.router, donc au-dessus de la route active quelle
// qu'elle soit) doit afficher le message + Réessayer et masquer le contenu
// de la route sous-jacente, peu importe cette route.
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

import 'package:app_patient/session/auth_cubit.dart';
import 'package:app_patient/session/auth_restore_overlay.dart';

class MockAuthCubit extends MockCubit<AuthState> implements AuthCubit {}

Widget _wrap(AuthCubit cubit) => BlocProvider<AuthCubit>.value(
      value: cubit,
      child: MaterialApp(
        theme: NubiaTheme.light,
        home: const AuthRestoreOverlay(child: Text('mes-rdv-content')),
      ),
    );

void main() {
  group('AuthRestoreOverlay — #6981', () {
    testWidgets(
        'AuthRestoreFailed masque la route active et affiche Réessayer, sans jamais montrer le login',
        (tester) async {
      final cubit = MockAuthCubit();
      when(() => cubit.state)
          .thenReturn(const AuthRestoreFailed('Pas de connexion internet.'));

      await tester.pumpWidget(_wrap(cubit));
      await tester.pump();

      expect(find.text('Pas de connexion internet.'), findsOneWidget);
      expect(find.text('Réessayer'), findsOneWidget);
      expect(find.text('mes-rdv-content'), findsNothing);
    });

    testWidgets('Réessayer relance AuthCubit.restore()', (tester) async {
      final cubit = MockAuthCubit();
      when(() => cubit.state)
          .thenReturn(const AuthRestoreFailed('Pas de connexion internet.'));
      when(() => cubit.restore()).thenAnswer((_) async {});

      await tester.pumpWidget(_wrap(cubit));
      await tester.pump();

      await tester.tap(find.text('Réessayer'));
      await tester.pump();

      verify(() => cubit.restore()).called(1);
    });

    testWidgets('état authentifié laisse la route active visible',
        (tester) async {
      final cubit = MockAuthCubit();
      when(() => cubit.state).thenReturn(const AuthUnknown());

      await tester.pumpWidget(_wrap(cubit));
      await tester.pump();

      expect(find.text('mes-rdv-content'), findsOneWidget);
    });
  });
}

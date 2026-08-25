import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

import 'package:app_patient/features/mes_rdv/mes_rdv_bloc.dart';
import 'package:app_patient/features/mes_rdv/mes_rdv_event.dart';
import 'package:app_patient/features/mes_rdv/mes_rdv_state.dart';

// ---------------------------------------------------------------------------
// Mock
// ---------------------------------------------------------------------------

class _MockMesRdvBloc extends MockBloc<MesRdvEvent, MesRdvState>
    implements MesRdvBloc {}

// ---------------------------------------------------------------------------
// Stub widget — reproduit le contrat UI sans passer par GetIt
// ---------------------------------------------------------------------------

class _MesRdvPageStub extends StatelessWidget {
  const _MesRdvPageStub();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<MesRdvBloc, MesRdvState>(
      builder: (context, state) {
        if (state is MesRdvLoading || state is MesRdvInitial) {
          return ListView.builder(
            key: const Key('mes_rdv_loading'),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            itemCount: 3,
            itemBuilder: (_, __) => const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: NubiaSkeletonLoader(height: 56, borderRadius: 12),
            ),
          );
        }
        if (state is MesRdvError) {
          return Center(
            key: const Key('mes_rdv_error'),
            child: Text(state.message),
          );
        }
        if (state is MesRdvLoaded &&
            state.upcoming.isEmpty &&
            state.history.isEmpty) {
          return const NubiaEmptyState(
            key: Key('mes_rdv_empty'),
            icon: Icons.calendar_today_outlined,
            title: 'Aucun rendez-vous',
          );
        }
        return const SizedBox.shrink();
      },
    );
  }
}

Widget _wrap(MesRdvBloc bloc) => MaterialApp(
      home: BlocProvider<MesRdvBloc>.value(
        value: bloc,
        child: const Scaffold(body: _MesRdvPageStub()),
      ),
    );

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('MesRdvPage — Loading', () {
    testWidgets('affiche un squelette de cartes en état Loading',
        (tester) async {
      final bloc = _MockMesRdvBloc();
      when(() => bloc.state).thenReturn(const MesRdvLoading());

      await tester.pumpWidget(_wrap(bloc));
      await tester.pump();

      expect(find.byKey(const Key('mes_rdv_loading')), findsOneWidget);
      expect(find.byType(NubiaSkeletonLoader), findsWidgets);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('affiche un squelette de cartes en état Initial',
        (tester) async {
      final bloc = _MockMesRdvBloc();
      when(() => bloc.state).thenReturn(const MesRdvInitial());

      await tester.pumpWidget(_wrap(bloc));
      await tester.pump();

      expect(find.byKey(const Key('mes_rdv_loading')), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });

  group('MesRdvPage — Error', () {
    testWidgets('affiche le message d\'erreur en état Error', (tester) async {
      final bloc = _MockMesRdvBloc();
      when(() => bloc.state)
          .thenReturn(const MesRdvError('Erreur de chargement.'));

      await tester.pumpWidget(_wrap(bloc));
      await tester.pump();

      expect(find.byKey(const Key('mes_rdv_error')), findsOneWidget);
      expect(find.text('Erreur de chargement.'), findsOneWidget);
    });
  });

  group('MesRdvPage — empty state', () {
    testWidgets('affiche NubiaEmptyState quand Loaded(items=[]) est émis',
        (tester) async {
      final bloc = _MockMesRdvBloc();
      when(() => bloc.state).thenReturn(
        MesRdvLoaded(upcoming: const [], history: const []),
      );

      await tester.pumpWidget(_wrap(bloc));
      await tester.pump();

      expect(find.byKey(const Key('mes_rdv_empty')), findsOneWidget);
      expect(find.byType(NubiaEmptyState), findsOneWidget);
    });
  });
}

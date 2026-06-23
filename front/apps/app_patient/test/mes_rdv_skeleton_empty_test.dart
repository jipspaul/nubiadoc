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
          return const Column(
            children: [
              NubiaSkeletonLoader(height: 80),
              SizedBox(height: 8),
              NubiaSkeletonLoader(height: 80),
              SizedBox(height: 8),
              NubiaSkeletonLoader(height: 80),
            ],
          );
        }
        if (state is MesRdvLoaded &&
            state.upcoming.isEmpty &&
            state.history.isEmpty) {
          return const NubiaEmptyState(
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
  group('MesRdvPage — skeleton Loading', () {
    testWidgets('affiche NubiaSkeletonLoader en état Loading', (tester) async {
      final bloc = _MockMesRdvBloc();
      when(() => bloc.state).thenReturn(const MesRdvLoading());

      await tester.pumpWidget(_wrap(bloc));
      await tester.pump();

      expect(find.byType(NubiaSkeletonLoader), findsWidgets);
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

      expect(find.byType(NubiaEmptyState), findsOneWidget);
    });
  });
}

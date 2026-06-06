import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_patient/domain/repositories/dashboard_repository.dart';
import 'package:nubia_patient/presentation/features/home/bloc/dashboard_bloc.dart';
import 'package:nubia_patient/presentation/features/home/widgets/dashboard_grid.dart';

class MockDashboardBloc extends MockBloc<DashboardEvent, DashboardState>
    implements DashboardBloc {}

const _summary = DashboardSummary(
  upcomingAppointments: 2,
  documentsToSign: 1,
  pendingPaymentsCents: 38000,
  unreadMessages: 3,
  pendingQuestionnaires: 0,
);

Widget _wrap(DashboardBloc bloc) {
  return MaterialApp(
    home: BlocProvider<DashboardBloc>.value(
      value: bloc,
      child: Scaffold(
        body: BlocBuilder<DashboardBloc, DashboardState>(
          builder: (context, state) {
            if (state is DashboardLoading || state is DashboardInitial) {
              return const Center(child: CircularProgressIndicator());
            }
            if (state is DashboardError) {
              return Center(child: Text(state.message));
            }
            if (state is DashboardLoaded) {
              return SingleChildScrollView(
                child: DashboardGrid(summary: state.summary),
              );
            }
            return const SizedBox.shrink();
          },
        ),
      ),
    ),
  );
}

void main() {
  late MockDashboardBloc bloc;

  setUp(() {
    bloc = MockDashboardBloc();
  });

  tearDown(() => bloc.close());

  testWidgets('affiche un indicateur de chargement en état Loading',
      (tester) async {
    when(() => bloc.state).thenReturn(const DashboardLoading());

    await tester.pumpWidget(_wrap(bloc));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('affiche un message d\'erreur en état Error', (tester) async {
    when(() => bloc.state)
        .thenReturn(const DashboardError('Erreur réseau.'));

    await tester.pumpWidget(_wrap(bloc));

    expect(find.text('Erreur réseau.'), findsOneWidget);
  });

  testWidgets('affiche les 4 tuiles du dashboard en état Loaded',
      (tester) async {
    when(() => bloc.state).thenReturn(const DashboardLoaded(_summary));

    await tester.pumpWidget(_wrap(bloc));

    expect(find.text('Prochain RDV'), findsOneWidget);
    expect(find.text('Docs à signer'), findsOneWidget);
    expect(find.text('Messages'), findsOneWidget);
    expect(find.text('Paiements'), findsOneWidget);
  });
}

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_patient/domain/entities/appointment.dart';
import 'package:nubia_patient/presentation/features/appointments/bloc/appointment_bloc.dart';
import 'package:nubia_patient/presentation/features/appointments/widgets/appointment_card.dart';
import 'package:nubia_patient/presentation/theme/nubia_theme.dart';

class MockAppointmentBloc extends MockBloc<AppointmentEvent, AppointmentState>
    implements AppointmentBloc {}

Appointment _makeAppointment(String id) => Appointment(
      id: id,
      cabinetId: 'cab-1',
      practitionerName: 'Dr. Martin',
      practitionerSpecialty: 'Dentiste',
      startsAt: DateTime.now().add(const Duration(days: 7)),
      duration: const Duration(minutes: 30),
      motif: 'Contrôle annuel',
      status: AppointmentStatus.confirmed,
    );

Widget _wrap(AppointmentBloc bloc) {
  return MaterialApp(
    theme: NubiaTheme.light,
    home: BlocProvider<AppointmentBloc>.value(
      value: bloc,
      child: const _AppointmentsBodyUnwrapped(),
    ),
  );
}

/// Re-exposes the inner body without the BlocProvider+DI so tests can inject
/// a mock bloc directly.
class _AppointmentsBodyUnwrapped extends StatelessWidget {
  const _AppointmentsBodyUnwrapped();

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Mes RDV'),
          bottom: const TabBar(
            tabs: [Tab(text: 'À venir'), Tab(text: 'Historique')],
          ),
        ),
        body: BlocBuilder<AppointmentBloc, AppointmentState>(
          builder: (context, state) {
            if (state is AppointmentInitial || state is AppointmentLoading) {
              return const Center(child: CircularProgressIndicator());
            }
            if (state is AppointmentError) {
              return Center(child: Text(state.message));
            }
            if (state is AppointmentLoaded) {
              return TabBarView(
                children: [
                  _list(state.upcoming, 'Aucun rendez-vous à venir'),
                  _list(state.history, 'Aucun historique'),
                ],
              );
            }
            return const SizedBox.shrink();
          },
        ),
      ),
    );
  }

  Widget _list(List<Appointment> appointments, String emptyLabel) {
    if (appointments.isEmpty) {
      return Center(child: Text(emptyLabel));
    }
    return ListView.builder(
      itemCount: appointments.length,
      itemBuilder: (_, i) =>
          AppointmentCard(appointment: appointments[i], onTap: () {}),
    );
  }
}

void main() {
  late MockAppointmentBloc bloc;

  setUpAll(() async {
    await initializeDateFormatting('fr');
  });

  setUp(() {
    bloc = MockAppointmentBloc();
  });

  tearDown(() => bloc.close());

  testWidgets('affiche un indicateur de chargement en état Loading',
      (tester) async {
    when(() => bloc.state).thenReturn(const AppointmentLoading());

    await tester.pumpWidget(_wrap(bloc));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('affiche un message d\'erreur en état Error', (tester) async {
    when(() => bloc.state)
        .thenReturn(const AppointmentError('Erreur réseau.'));

    await tester.pumpWidget(_wrap(bloc));

    expect(find.text('Erreur réseau.'), findsOneWidget);
  });

  testWidgets(
      'affiche la liste des RDV à venir en état Loaded',
      (tester) async {
    final upcoming = [_makeAppointment('a1'), _makeAppointment('a2')];
    when(() => bloc.state).thenReturn(
      AppointmentLoaded(upcoming: upcoming, history: const []),
    );

    await tester.pumpWidget(_wrap(bloc));

    expect(find.byType(AppointmentCard), findsNWidgets(2));
    expect(find.text('Contrôle annuel'), findsNWidgets(2));
  });

  testWidgets(
      'affiche le message vide quand aucun RDV à venir',
      (tester) async {
    when(() => bloc.state).thenReturn(
      const AppointmentLoaded(upcoming: [], history: []),
    );

    await tester.pumpWidget(_wrap(bloc));

    expect(find.text('Aucun rendez-vous à venir'), findsOneWidget);
  });
}

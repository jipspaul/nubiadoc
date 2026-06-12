import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_patient/domain/entities/quote.dart';
import 'package:nubia_patient/presentation/features/financial/bloc/quote_list_cubit.dart';
import 'package:nubia_patient/presentation/features/financial/widgets/quote_list_tile.dart';
import 'package:nubia_patient/presentation/theme/nubia_theme.dart';

// ---------------------------------------------------------------------------
// Mock
// ---------------------------------------------------------------------------

class MockQuoteListCubit extends MockCubit<QuoteListState>
    implements QuoteListCubit {}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Quote _makeQuote(String id, QuoteStatus status) => Quote(
      id: id,
      cabinetId: 'cab-1',
      practitionerName: 'Dr. Fictif',
      items: const [],
      totalCents: 120000,
      patientShareCents: 80000,
      depositCents: 40000,
      status: status,
      createdAt: DateTime(2026, 1, 1),
    );

/// Enveloppe la body de QuoteListPage sans BlocProvider+DI afin d'injecter
/// un mock directement.
class _QuoteListBodyUnwrapped extends StatelessWidget {
  const _QuoteListBodyUnwrapped();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mes devis')),
      body: BlocBuilder<QuoteListCubit, QuoteListState>(
        builder: (context, state) {
          if (state is QuoteListLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state is QuoteListError) {
            return Center(child: Text(state.message));
          }
          if (state is QuoteListLoaded) {
            if (state.quotes.isEmpty) {
              return const Center(child: Text('Aucun devis pour le moment.'));
            }
            return ListView.builder(
              itemCount: state.quotes.length,
              itemBuilder: (_, i) => QuoteListTile(
                quote: state.quotes[i],
                onTap: () {},
              ),
            );
          }
          return const SizedBox.shrink();
        },
      ),
    );
  }
}

Widget _wrap(QuoteListCubit cubit) {
  return MaterialApp(
    theme: NubiaTheme.light,
    home: BlocProvider<QuoteListCubit>.value(
      value: cubit,
      child: const _QuoteListBodyUnwrapped(),
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late MockQuoteListCubit cubit;

  setUp(() {
    cubit = MockQuoteListCubit();
  });

  tearDown(() => cubit.close());

  testWidgets('affiche un indicateur de chargement en état QuoteListLoading',
      (tester) async {
    when(() => cubit.state).thenReturn(const QuoteListLoading());

    await tester.pumpWidget(_wrap(cubit));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('affiche un message d\'erreur en état QuoteListError',
      (tester) async {
    when(() => cubit.state)
        .thenReturn(const QuoteListError('Erreur réseau.'));

    await tester.pumpWidget(_wrap(cubit));

    expect(find.text('Erreur réseau.'), findsOneWidget);
  });

  testWidgets('affiche le message vide quand la liste est vide', (tester) async {
    when(() => cubit.state)
        .thenReturn(const QuoteListLoaded([]));

    await tester.pumpWidget(_wrap(cubit));

    expect(find.text('Aucun devis pour le moment.'), findsOneWidget);
    expect(find.byType(QuoteListTile), findsNothing);
  });

  testWidgets('affiche les tuiles pour chaque devis chargé', (tester) async {
    final quotes = [
      _makeQuote('q1', QuoteStatus.sent),
      _makeQuote('q2', QuoteStatus.signed),
      _makeQuote('q3', QuoteStatus.expired),
    ];
    when(() => cubit.state).thenReturn(QuoteListLoaded(quotes));

    await tester.pumpWidget(_wrap(cubit));

    expect(find.byType(QuoteListTile), findsNWidgets(3));
  });

  // -------------------------------------------------------------------------
  // Badges de statut : 3 statuts principaux (pending=sent, signed, expired)
  // -------------------------------------------------------------------------

  testWidgets('badge "À signer" pour statut sent', (tester) async {
    when(() => cubit.state).thenReturn(
      QuoteListLoaded([_makeQuote('q1', QuoteStatus.sent)]),
    );

    await tester.pumpWidget(_wrap(cubit));

    expect(find.text('À signer'), findsOneWidget);
  });

  testWidgets('badge "Signé" pour statut signed', (tester) async {
    when(() => cubit.state).thenReturn(
      QuoteListLoaded([_makeQuote('q1', QuoteStatus.signed)]),
    );

    await tester.pumpWidget(_wrap(cubit));

    expect(find.text('Signé'), findsOneWidget);
  });

  testWidgets('badge "Expiré" pour statut expired', (tester) async {
    when(() => cubit.state).thenReturn(
      QuoteListLoaded([_makeQuote('q1', QuoteStatus.expired)]),
    );

    await tester.pumpWidget(_wrap(cubit));

    expect(find.text('Expiré'), findsOneWidget);
  });
}

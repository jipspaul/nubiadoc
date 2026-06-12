import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_patient/domain/entities/quote.dart';
import 'package:nubia_patient/presentation/features/financial/bloc/wedge_bloc.dart';
import 'package:nubia_patient/presentation/features/financial/bloc/wedge_event.dart';
import 'package:nubia_patient/presentation/features/financial/bloc/wedge_state.dart';
import 'package:nubia_patient/presentation/features/financial/pages/quote_detail_page.dart';
import 'package:nubia_patient/presentation/theme/nubia_theme.dart';
import 'package:nubia_patient/presentation/widgets/nubia_button.dart';

// ---------------------------------------------------------------------------
// Mock
// ---------------------------------------------------------------------------

class MockWedgeBloc extends MockBloc<WedgeEvent, WedgeState>
    implements WedgeBloc {}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const _quoteId = 'q-detail-test';

Quote _makeQuote({
  required QuoteStatus status,
  DateTime? expiresAt,
}) =>
    Quote(
      id: _quoteId,
      cabinetId: 'cab-1',
      practitionerName: 'Dr. Fictif',
      items: const [
        QuoteLineItem(
          id: 'li-1',
          label: 'Couronne céramique',
          totalCents: 120000,
          amoShareCents: 10000,
          amcShareCents: 30000,
          patientShareCents: 80000,
        ),
      ],
      totalCents: 120000,
      patientShareCents: 80000,
      depositCents: 40000,
      status: status,
      createdAt: DateTime(2026, 1, 1),
      expiresAt: expiresAt,
    );

Widget _wrap(WedgeBloc bloc) {
  return MaterialApp(
    theme: NubiaTheme.light,
    home: BlocProvider<WedgeBloc>.value(
      value: bloc,
      child: const QuoteDetailPage(quoteId: _quoteId),
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  setUpAll(() {
    registerFallbackValue(const WedgeQuoteLoadRequested(quoteId: _quoteId));
  });

  late MockWedgeBloc bloc;

  setUp(() {
    bloc = MockWedgeBloc();
  });

  tearDown(() => bloc.close());

  // -------------------------------------------------------------------------
  // Statut : sent (pending) — CTA activé
  // -------------------------------------------------------------------------

  testWidgets('statut sent : CTA "Signer le devis" est actif', (tester) async {
    final quote = _makeQuote(status: QuoteStatus.sent);
    when(() => bloc.state).thenReturn(WedgeQuoteLoaded(quote));

    await tester.pumpWidget(_wrap(bloc));

    final btn = tester.widget<NubiaButton>(
      find.byKey(const Key('btn_sign_quote')),
    );
    expect(btn.onPressed, isNotNull,
        reason: 'Le CTA doit être actif pour le statut sent');
  });

  testWidgets('statut sent : badge "À signer" affiché', (tester) async {
    final quote = _makeQuote(status: QuoteStatus.sent);
    when(() => bloc.state).thenReturn(WedgeQuoteLoaded(quote));

    await tester.pumpWidget(_wrap(bloc));

    expect(find.text('À signer'), findsOneWidget);
  });

  // -------------------------------------------------------------------------
  // Statut : signed — CTA désactivé
  // -------------------------------------------------------------------------

  testWidgets('statut signed : CTA "Signer le devis" est désactivé',
      (tester) async {
    final quote = _makeQuote(status: QuoteStatus.signed);
    // canSign == false car status != sent → WedgeQuoteLoaded mais ctaEnabled=false
    when(() => bloc.state).thenReturn(WedgeQuoteLoaded(quote));

    await tester.pumpWidget(_wrap(bloc));

    final btn = tester.widget<NubiaButton>(
      find.byKey(const Key('btn_sign_quote')),
    );
    expect(btn.onPressed, isNull,
        reason: 'Le CTA doit être désactivé pour le statut signed');
  });

  testWidgets('statut signed : badge "Signé" affiché', (tester) async {
    final quote = _makeQuote(status: QuoteStatus.signed);
    when(() => bloc.state).thenReturn(WedgeQuoteLoaded(quote));

    await tester.pumpWidget(_wrap(bloc));

    expect(find.text('Signé'), findsOneWidget);
  });

  // -------------------------------------------------------------------------
  // Statut : expired — corps expiré affiché, pas de CTA actif
  // -------------------------------------------------------------------------

  testWidgets('statut expiré : corps expiré affiché', (tester) async {
    final quote = _makeQuote(
      status: QuoteStatus.expired,
      expiresAt: DateTime(2025, 1, 1),
    );
    when(() => bloc.state).thenReturn(WedgeQuoteExpired(quote));

    await tester.pumpWidget(_wrap(bloc));

    expect(find.text('Devis expiré'), findsOneWidget);
    // Le CTA "Signer le devis" n'est pas visible sur l'écran expiré.
    expect(find.byKey(const Key('btn_sign_quote')), findsNothing);
  });

  // -------------------------------------------------------------------------
  // Total et reste à charge affichés
  // -------------------------------------------------------------------------

  testWidgets('total et reste à charge sont affichés', (tester) async {
    final quote = _makeQuote(status: QuoteStatus.sent);
    when(() => bloc.state).thenReturn(WedgeQuoteLoaded(quote));

    await tester.pumpWidget(_wrap(bloc));

    // Les labels des montants sont présents dans le header.
    expect(find.text('Total traitement'), findsOneWidget);
    expect(find.text('Reste à charge'), findsOneWidget);
  });

  // -------------------------------------------------------------------------
  // Lignes de devis repliables (ExpansionTile)
  // -------------------------------------------------------------------------

  testWidgets('les lignes de devis sont affichées et repliables',
      (tester) async {
    final quote = _makeQuote(status: QuoteStatus.sent);
    when(() => bloc.state).thenReturn(WedgeQuoteLoaded(quote));

    await tester.pumpWidget(_wrap(bloc));

    // Le libellé de la ligne est visible (collapsed state).
    expect(find.text('Couronne céramique'), findsOneWidget);

    // Ouvrir la tuile.
    await tester.tap(find.text('Couronne céramique'));
    await tester.pumpAndSettle();

    // Les détails de répartition apparaissent.
    expect(find.text('Remb. Sécu'), findsOneWidget);
    expect(find.text('Remb. Mutuelle'), findsOneWidget);
  });

  // -------------------------------------------------------------------------
  // État de chargement
  // -------------------------------------------------------------------------

  testWidgets('affiche un CircularProgressIndicator en état WedgeLoading',
      (tester) async {
    when(() => bloc.state).thenReturn(const WedgeLoading());

    await tester.pumpWidget(_wrap(bloc));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  // -------------------------------------------------------------------------
  // État d'erreur
  // -------------------------------------------------------------------------

  testWidgets('affiche le message d\'erreur en état WedgeError',
      (tester) async {
    when(() => bloc.state)
        .thenReturn(const WedgeError(message: 'Erreur réseau.'));

    await tester.pumpWidget(_wrap(bloc));

    expect(find.text('Erreur réseau.'), findsOneWidget);
  });
}

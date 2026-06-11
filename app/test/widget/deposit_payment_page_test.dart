import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_patient/domain/entities/quote.dart';
import 'package:nubia_patient/presentation/features/financial/bloc/wedge_bloc.dart';
import 'package:nubia_patient/presentation/features/financial/bloc/wedge_event.dart';
import 'package:nubia_patient/presentation/features/financial/bloc/wedge_state.dart';
import 'package:nubia_patient/presentation/features/financial/pages/deposit_payment_page.dart';
import 'package:nubia_patient/presentation/widgets/nubia_button.dart';

// ---------------------------------------------------------------------------
// Mock
// ---------------------------------------------------------------------------

class MockWedgeBloc extends MockBloc<WedgeEvent, WedgeState>
    implements WedgeBloc {}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const _quoteId = 'q-widget-test';

Quote _signedQuote() => Quote(
      id: _quoteId,
      cabinetId: 'cab-1',
      practitionerName: 'Dr. Fictif',
      items: const [],
      totalCents: 125000,
      patientShareCents: 38000,
      depositCents: 38000,
      status: QuoteStatus.signed,
      createdAt: DateTime(2026, 1, 1),
    );

Widget _wrap(WedgeBloc bloc) {
  return MaterialApp(
    home: BlocProvider<WedgeBloc>.value(
      value: bloc,
      child: const DepositPaymentPage(quoteId: _quoteId),
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  setUpAll(() {
    // WedgeEvent est sealed : on enregistre une instance concrète valide
    // comme fallback pour captureAny().
    registerFallbackValue(const WedgeDepositRetryRequested());
  });

  late MockWedgeBloc bloc;

  setUp(() {
    bloc = MockWedgeBloc();
  });

  tearDown(() => bloc.close());

  // -------------------------------------------------------------------------
  // État : chargement initial (WedgeLoading)
  // -------------------------------------------------------------------------

  testWidgets('affiche un CircularProgressIndicator en état WedgeLoading',
      (tester) async {
    when(() => bloc.state).thenReturn(const WedgeLoading());

    await tester.pumpWidget(_wrap(bloc));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    // Les boutons ne doivent pas être visibles.
    expect(find.byKey(const Key('btn_card_pay')), findsNothing);
  });

  // -------------------------------------------------------------------------
  // État : signature terminée → boutons actifs (pas disabled)
  // -------------------------------------------------------------------------

  testWidgets(
      'affiche les boutons de paiement actifs en état WedgeSignatureDone',
      (tester) async {
    when(() => bloc.state).thenReturn(WedgeSignatureDone(_signedQuote()));

    await tester.pumpWidget(_wrap(bloc));

    // Le bouton carte est présent et actif.
    final cardBtn = tester.widget<NubiaButton>(
      find.byKey(const Key('btn_card_pay')),
    );
    expect(cardBtn.onPressed, isNotNull,
        reason: 'Le bouton doit être actif (non disabled)');

    // Le bouton Apple/Google Pay est présent et actif.
    expect(find.byKey(const Key('btn_native_pay')), findsOneWidget);

    // Pas de message d'erreur visible.
    expect(find.byKey(const Key('btn_retry_payment')), findsNothing);
  });

  // -------------------------------------------------------------------------
  // État : paiement en cours → boutons disabled (isLoading = true)
  // -------------------------------------------------------------------------

  testWidgets('désactive les boutons en état WedgePaymentInProgress',
      (tester) async {
    when(() => bloc.state).thenReturn(
      WedgePaymentInProgress(
        quote: _signedQuote(),
        idempotencyKey: 'q-widget-test-dep-111',
      ),
    );

    await tester.pumpWidget(_wrap(bloc));

    final cardBtn = tester.widget<NubiaButton>(
      find.byKey(const Key('btn_card_pay')),
    );
    // NubiaButton désactive onPressed quand isLoading = true.
    expect(cardBtn.isLoading, isTrue);
  });

  // -------------------------------------------------------------------------
  // État : erreur avec devis → bouton Réessayer visible, carte masquée
  // -------------------------------------------------------------------------

  testWidgets('affiche le bouton Réessayer et le message d\'erreur en WedgeError',
      (tester) async {
    when(() => bloc.state).thenReturn(
      WedgeError(
        message: 'Paiement refusé.',
        quote: _signedQuote(),
      ),
    );

    await tester.pumpWidget(_wrap(bloc));

    // Bouton retry présent.
    expect(find.byKey(const Key('btn_retry_payment')), findsOneWidget);

    // Message d'erreur affiché.
    expect(find.text('Paiement refusé.'), findsOneWidget);

    // Les boutons de paiement initiaux sont masqués en état erreur.
    expect(find.byKey(const Key('btn_card_pay')), findsNothing);
    expect(find.byKey(const Key('btn_native_pay')), findsNothing);
  });

  // -------------------------------------------------------------------------
  // État : erreur sans devis → fallback chargement (pas de retry possible)
  // -------------------------------------------------------------------------

  testWidgets(
      'affiche le fallback chargement si WedgeError sans quote associé',
      (tester) async {
    when(() => bloc.state).thenReturn(
      const WedgeError(message: 'Erreur inattendue.'),
    );

    await tester.pumpWidget(_wrap(bloc));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byKey(const Key('btn_retry_payment')), findsNothing);
  });

  // -------------------------------------------------------------------------
  // Interaction : tap sur « Réessayer » dispatch WedgeDepositRetryRequested
  // -------------------------------------------------------------------------

  testWidgets('tap sur Réessayer dispatch WedgeDepositRetryRequested',
      (tester) async {
    when(() => bloc.state).thenReturn(
      WedgeError(
        message: 'Paiement refusé.',
        quote: _signedQuote(),
      ),
    );

    await tester.pumpWidget(_wrap(bloc));
    await tester.tap(find.byKey(const Key('btn_retry_payment')));

    verify(() => bloc.add(const WedgeDepositRetryRequested())).called(1);
  });

  // -------------------------------------------------------------------------
  // Interaction : tap sur « Payer par carte » dispatch WedgeDepositRequested
  // -------------------------------------------------------------------------

  testWidgets('tap sur Payer par carte dispatch WedgeDepositRequested',
      (tester) async {
    when(() => bloc.state).thenReturn(WedgeSignatureDone(_signedQuote()));

    await tester.pumpWidget(_wrap(bloc));
    await tester.tap(find.byKey(const Key('btn_card_pay')));

    final captured = verify(() => bloc.add(captureAny())).captured;
    expect(captured.last, isA<WedgeDepositRequested>());

    final event = captured.last as WedgeDepositRequested;
    // La clé doit contenir l'id du devis et un suffixe de timestamp.
    expect(event.idempotencyKey, startsWith('$_quoteId-dep-'),
        reason: 'Format : <quoteId>-dep-<microseconds>');
  });
}

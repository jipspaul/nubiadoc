import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_patient/features/financial/financial_bloc.dart';
import 'package:app_patient/features/financial/financial_event.dart';
import 'package:app_patient/features/financial/financial_page.dart';
import 'package:app_patient/features/financial/financial_state.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class MockGetPendingQuotesUseCase extends Mock
    implements GetPendingQuotesUseCase {}

class MockGetQuoteByIdUseCase extends Mock implements GetQuoteByIdUseCase {}

class MockInitiateSignatureUseCase extends Mock
    implements InitiateSignatureUseCase {}

class MockInitiateDepositUseCase extends Mock
    implements InitiateDepositUseCase {}

class MockGetDocumentSignedUrlUseCase extends Mock
    implements GetDocumentSignedUrlUseCase {}

class MockGetPatientQuoteAttachmentsUseCase extends Mock
    implements GetPatientQuoteAttachmentsUseCase {}

class MockGetPatientQuoteAttestationUseCase extends Mock
    implements GetPatientQuoteAttestationUseCase {}

class MockSignPatientQuoteAttestationUseCase extends Mock
    implements SignPatientQuoteAttestationUseCase {}

class MockGetQuotePaymentScheduleUseCase extends Mock
    implements GetQuotePaymentScheduleUseCase {}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

final _quote = Quote(
  id: 'q-1',
  cabinetId: 'cab-1',
  practitionerName: 'Dr Lemaire',
  items: const [],
  totalCents: 15000,
  patientShareCents: 8000,
  depositCents: 4000,
  status: QuoteStatus.sent,
  createdAt: DateTime(2026, 6, 1),
);

/// Devis avec une ligne classifiée `modere` (#4061) : doit déclencher
/// l'encart d'alternative RAC 0 sur l'écran détail.
final _quoteWithModereItem = Quote(
  id: 'q-modere',
  cabinetId: 'cab-1',
  practitionerName: 'Dr Lemaire',
  items: const [
    QuoteLineItem(
      id: 'item-1',
      label: 'Couronne céramo-métallique',
      totalCents: 30000,
      amoShareCents: 10000,
      amcShareCents: 5000,
      patientShareCents: 15000,
      panierSante: PanierSante.modere,
    ),
  ],
  totalCents: 30000,
  patientShareCents: 15000,
  depositCents: 0,
  status: QuoteStatus.sent,
  createdAt: DateTime(2026, 6, 1),
);

/// Devis signé avec un PDF horodaté disponible dans le coffre (#5243) : doit
/// afficher le CTA secondaire « Télécharger le devis signé ».
final _signedQuoteWithDocument = Quote(
  id: 'q-signed',
  cabinetId: 'cab-1',
  practitionerName: 'Dr Lemaire',
  items: const [],
  totalCents: 15000,
  patientShareCents: 8000,
  depositCents: 4000,
  status: QuoteStatus.signed,
  createdAt: DateTime(2026, 6, 1),
  documentId: 'doc-1',
);

/// Attestation d'information non signée — bloque la signature du devis
/// tant qu'elle n'est pas signée (#7201/#7203).
final _pendingAttestation = QuoteAttestation(
  id: 'att-1',
  body: "Ce traitement comporte les risques suivants : ...",
  createdAt: DateTime(2026, 6, 1),
);

final _signedAttestation = QuoteAttestation(
  id: 'att-1',
  body: _pendingAttestation.body,
  signedAt: DateTime(2026, 6, 2),
  createdAt: DateTime(2026, 6, 1),
);

/// Échéancier `active` à 3 jalons datés posé par le praticien sur
/// `q-signed` (#7018, repro QA-20260915-28).
final _activePaymentSchedule = PaymentSchedule(
  id: 'sched-1',
  quoteId: 'q-signed',
  totalAmountCents: 30000,
  installments: [
    PaymentScheduleInstallment(
      date: DateTime(2026, 10, 1),
      amountCents: 10000,
      status: InstallmentStatus.pending,
    ),
    PaymentScheduleInstallment(
      date: DateTime(2026, 11, 1),
      amountCents: 10000,
      status: InstallmentStatus.pending,
    ),
    PaymentScheduleInstallment(
      date: DateTime(2026, 12, 1),
      amountCents: 10000,
      status: InstallmentStatus.pending,
    ),
  ],
  status: PaymentScheduleStatus.active,
  createdAt: DateTime(2026, 9, 1),
);

FinancialBloc _makeBloc({
  required MockGetPendingQuotesUseCase getPendingQuotes,
  required MockGetQuoteByIdUseCase getQuoteById,
  required MockInitiateSignatureUseCase initiateSignature,
  required MockInitiateDepositUseCase initiateDeposit,
  required MockGetDocumentSignedUrlUseCase getDocumentSignedUrl,
  required MockGetPatientQuoteAttachmentsUseCase getQuoteAttachments,
  required MockGetPatientQuoteAttestationUseCase getQuoteAttestation,
  required MockSignPatientQuoteAttestationUseCase signQuoteAttestation,
  MockGetQuotePaymentScheduleUseCase? getQuotePaymentSchedule,
}) {
  // Défaut neutre (aucun échéancier, #7018) : seuls les tests dédiés à
  // l'échéancier ont besoin de le stubber explicitement.
  final paymentSchedule =
      getQuotePaymentSchedule ?? MockGetQuotePaymentScheduleUseCase();
  if (getQuotePaymentSchedule == null) {
    when(() => paymentSchedule(any()))
        .thenAnswer((_) async => const Right(null));
  }
  return FinancialBloc(
    getPendingQuotes: getPendingQuotes,
    getQuoteById: getQuoteById,
    initiateSignature: initiateSignature,
    initiateDeposit: initiateDeposit,
    getDocumentSignedUrl: getDocumentSignedUrl,
    getQuoteAttachments: getQuoteAttachments,
    getQuoteAttestation: getQuoteAttestation,
    signQuoteAttestation: signQuoteAttestation,
    getQuotePaymentSchedule: paymentSchedule,
  );
}

Widget _wrap(FinancialBloc bloc) => MaterialApp(
      theme: NubiaTheme.light,
      home: BlocProvider.value(
        value: bloc,
        child: const Scaffold(body: FinancialPage()),
      ),
    );

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late MockGetPendingQuotesUseCase mockGetPendingQuotes;
  late MockGetQuoteByIdUseCase mockGetQuoteById;
  late MockInitiateSignatureUseCase mockInitiateSignature;
  late MockInitiateDepositUseCase mockInitiateDeposit;
  late MockGetDocumentSignedUrlUseCase mockGetDocumentSignedUrl;
  late MockGetPatientQuoteAttachmentsUseCase mockGetQuoteAttachments;
  late MockGetPatientQuoteAttestationUseCase mockGetQuoteAttestation;
  late MockSignPatientQuoteAttestationUseCase mockSignQuoteAttestation;

  setUpAll(() {
    registerFallbackValue(_quote);
  });

  setUp(() {
    mockGetPendingQuotes = MockGetPendingQuotesUseCase();
    mockGetQuoteById = MockGetQuoteByIdUseCase();
    mockInitiateSignature = MockInitiateSignatureUseCase();
    mockInitiateDeposit = MockInitiateDepositUseCase();
    mockGetDocumentSignedUrl = MockGetDocumentSignedUrlUseCase();
    mockGetQuoteAttachments = MockGetPatientQuoteAttachmentsUseCase();
    mockGetQuoteAttestation = MockGetPatientQuoteAttestationUseCase();
    mockSignQuoteAttestation = MockSignPatientQuoteAttestationUseCase();
    // Défaut neutre (aucune pièce jointe/attestation) : la plupart des tests
    // de cette suite ne portent pas sur #7201, ils ne doivent pas avoir à le
    // stubber explicitement.
    when(() => mockGetQuoteAttachments(any()))
        .thenAnswer((_) async => const Right([]));
    when(() => mockGetQuoteAttestation(any()))
        .thenAnswer((_) async => const Right(null));
  });

  group('FinancialPage widget', () {
    testWidgets('affiche le spinner en état initial', (tester) async {
      final bloc = _makeBloc(
        getPendingQuotes: mockGetPendingQuotes,
        getQuoteById: mockGetQuoteById,
        initiateSignature: mockInitiateSignature,
        initiateDeposit: mockInitiateDeposit,
        getDocumentSignedUrl: mockGetDocumentSignedUrl,
        getQuoteAttachments: mockGetQuoteAttachments,
        getQuoteAttestation: mockGetQuoteAttestation,
        signQuoteAttestation: mockSignQuoteAttestation,
      );

      await tester.pumpWidget(_wrap(bloc));

      expect(find.byKey(const Key('financial_loading')), findsOneWidget);
    });

    testWidgets('affiche "Aucun devis" quand la liste est vide',
        (tester) async {
      when(() => mockGetPendingQuotes())
          .thenAnswer((_) async => const Right([]));

      final bloc = _makeBloc(
        getPendingQuotes: mockGetPendingQuotes,
        getQuoteById: mockGetQuoteById,
        initiateSignature: mockInitiateSignature,
        initiateDeposit: mockInitiateDeposit,
        getDocumentSignedUrl: mockGetDocumentSignedUrl,
        getQuoteAttachments: mockGetQuoteAttachments,
        getQuoteAttestation: mockGetQuoteAttestation,
        signQuoteAttestation: mockSignQuoteAttestation,
      );
      bloc.add(const FinancialLoadRequested());

      await tester.pumpWidget(_wrap(bloc));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('financial_empty')), findsOneWidget);
    });

    testWidgets('affiche la liste des devis quand chargée', (tester) async {
      when(() => mockGetPendingQuotes())
          .thenAnswer((_) async => Right([_quote]));

      final bloc = _makeBloc(
        getPendingQuotes: mockGetPendingQuotes,
        getQuoteById: mockGetQuoteById,
        initiateSignature: mockInitiateSignature,
        initiateDeposit: mockInitiateDeposit,
        getDocumentSignedUrl: mockGetDocumentSignedUrl,
        getQuoteAttachments: mockGetQuoteAttachments,
        getQuoteAttestation: mockGetQuoteAttestation,
        signQuoteAttestation: mockSignQuoteAttestation,
      );
      bloc.add(const FinancialLoadRequested());

      await tester.pumpWidget(_wrap(bloc));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('financial_list')), findsOneWidget);
      expect(find.byKey(const Key('quote_item_q-1')), findsOneWidget);
      expect(find.text('Dr Lemaire'), findsOneWidget);
    });

    testWidgets('pull-to-refresh déclenche FinancialLoadRequested',
        (tester) async {
      var callCount = 0;
      when(() => mockGetPendingQuotes()).thenAnswer((_) async {
        callCount++;
        return Right([_quote]);
      });

      final bloc = _makeBloc(
        getPendingQuotes: mockGetPendingQuotes,
        getQuoteById: mockGetQuoteById,
        initiateSignature: mockInitiateSignature,
        initiateDeposit: mockInitiateDeposit,
        getDocumentSignedUrl: mockGetDocumentSignedUrl,
        getQuoteAttachments: mockGetQuoteAttachments,
        getQuoteAttestation: mockGetQuoteAttestation,
        signQuoteAttestation: mockSignQuoteAttestation,
      );
      bloc.add(const FinancialLoadRequested());

      await tester.pumpWidget(_wrap(bloc));
      await tester.pumpAndSettle();

      expect(callCount, 1);
      expect(find.byKey(const Key('financial_list')), findsOneWidget);

      await tester.fling(
        find.byKey(const Key('financial_list')),
        const Offset(0, 300),
        1000,
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      expect(callCount, 2);
    });

    testWidgets('affiche le message d\'erreur en état erreur', (tester) async {
      when(() => mockGetPendingQuotes()).thenAnswer(
          (_) async => const Left(NetworkFailure('Erreur réseau.')));

      final bloc = _makeBloc(
        getPendingQuotes: mockGetPendingQuotes,
        getQuoteById: mockGetQuoteById,
        initiateSignature: mockInitiateSignature,
        initiateDeposit: mockInitiateDeposit,
        getDocumentSignedUrl: mockGetDocumentSignedUrl,
        getQuoteAttachments: mockGetQuoteAttachments,
        getQuoteAttestation: mockGetQuoteAttestation,
        signQuoteAttestation: mockSignQuoteAttestation,
      );
      bloc.add(const FinancialLoadRequested());

      await tester.pumpWidget(_wrap(bloc));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('financial_error')), findsOneWidget);
      expect(find.text('Erreur réseau.'), findsOneWidget);
    });

    testWidgets(
        'affiche l\'encart alternative RAC 0 quand une ligne est panier=modere (#4061)',
        (tester) async {
      when(() => mockGetPendingQuotes())
          .thenAnswer((_) async => Right([_quoteWithModereItem]));
      when(() => mockGetQuoteById(any()))
          .thenAnswer((_) async => Right(_quoteWithModereItem));

      final bloc = _makeBloc(
        getPendingQuotes: mockGetPendingQuotes,
        getQuoteById: mockGetQuoteById,
        initiateSignature: mockInitiateSignature,
        initiateDeposit: mockInitiateDeposit,
        getDocumentSignedUrl: mockGetDocumentSignedUrl,
        getQuoteAttachments: mockGetQuoteAttachments,
        getQuoteAttestation: mockGetQuoteAttestation,
        signQuoteAttestation: mockSignQuoteAttestation,
      );
      bloc.add(const FinancialLoadRequested());

      await tester.pumpWidget(_wrap(bloc));
      await tester.pumpAndSettle();

      bloc.add(const FinancialQuoteSelected('q-modere'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('rac0_alternative_banner')), findsOneWidget);
      expect(find.byKey(const Key('panier_badge_modere')), findsOneWidget);
      expect(find.text('Alternative reste à charge zéro disponible'),
          findsOneWidget);
    });

    testWidgets('affiche la ventilation Part AMO / Part AMC par ligne (#4063)',
        (tester) async {
      when(() => mockGetPendingQuotes())
          .thenAnswer((_) async => Right([_quoteWithModereItem]));
      when(() => mockGetQuoteById(any()))
          .thenAnswer((_) async => Right(_quoteWithModereItem));

      final bloc = _makeBloc(
        getPendingQuotes: mockGetPendingQuotes,
        getQuoteById: mockGetQuoteById,
        initiateSignature: mockInitiateSignature,
        initiateDeposit: mockInitiateDeposit,
        getDocumentSignedUrl: mockGetDocumentSignedUrl,
        getQuoteAttachments: mockGetQuoteAttachments,
        getQuoteAttestation: mockGetQuoteAttestation,
        signQuoteAttestation: mockSignQuoteAttestation,
      );
      bloc.add(const FinancialLoadRequested());

      await tester.pumpWidget(_wrap(bloc));
      await tester.pumpAndSettle();

      bloc.add(const FinancialQuoteSelected('q-modere'));
      await tester.pumpAndSettle();

      // item-1 : amoShareCents=10000 (100 €), amcShareCents=5000 (50 €).
      expect(find.textContaining('Part AMO : 100 €'), findsOneWidget);
      expect(find.textContaining('Part AMC : 50 €'), findsOneWidget);
    });

    testWidgets(
        'affiche la barre de ventilation AMO/AMC/RAC avec segments '
        'proportionnels et légende soustractive (#5234)', (tester) async {
      when(() => mockGetPendingQuotes())
          .thenAnswer((_) async => Right([_quoteWithModereItem]));
      when(() => mockGetQuoteById(any()))
          .thenAnswer((_) async => Right(_quoteWithModereItem));

      final bloc = _makeBloc(
        getPendingQuotes: mockGetPendingQuotes,
        getQuoteById: mockGetQuoteById,
        initiateSignature: mockInitiateSignature,
        initiateDeposit: mockInitiateDeposit,
        getDocumentSignedUrl: mockGetDocumentSignedUrl,
        getQuoteAttachments: mockGetQuoteAttachments,
        getQuoteAttestation: mockGetQuoteAttestation,
        signQuoteAttestation: mockSignQuoteAttestation,
      );
      bloc.add(const FinancialLoadRequested());

      await tester.pumpWidget(_wrap(bloc));
      await tester.pumpAndSettle();

      bloc.add(const FinancialQuoteSelected('q-modere'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('ventilation_bar')), findsOneWidget);

      // Σ amoShareCents=10000, Σ amcShareCents=5000, RAC=patientShareCents=15000.
      final amoSize =
          tester.getSize(find.byKey(const Key('ventilation_segment_amo')));
      final amcSize =
          tester.getSize(find.byKey(const Key('ventilation_segment_amc')));
      final racSize =
          tester.getSize(find.byKey(const Key('ventilation_segment_rac')));
      final totalWidth = amoSize.width + amcSize.width + racSize.width;

      expect(amoSize.width / totalWidth, closeTo(10000 / 30000, 0.05));
      expect(amcSize.width / totalWidth, closeTo(5000 / 30000, 0.05));
      expect(racSize.width / totalWidth, closeTo(15000 / 30000, 0.05));

      // Légende soustractive : AMO puis AMC jusqu'au reste à votre charge.
      expect(
        find.descendant(
          of: find.byKey(const Key('ventilation_legend_amo')),
          matching: find.text('Assurance Maladie (AMO)'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('ventilation_legend_amo')),
          matching: find.text(formatQuoteCents(-10000)),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('ventilation_legend_amc')),
          matching: find.text('Mutuelle'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('ventilation_legend_amc')),
          matching: find.text(formatQuoteCents(-5000)),
        ),
        findsOneWidget,
      );
      expect(find.text('Reste à votre charge'), findsOneWidget);
      expect(
        find.byKey(const Key('ventilation_rac_value')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<Text>(find.byKey(const Key('ventilation_rac_value')))
            .data,
        formatQuoteCents(_quoteWithModereItem.patientShareCents),
      );
    });

    testWidgets(
        'n\'affiche pas l\'encart alternative RAC 0 sans ligne panier=modere',
        (tester) async {
      when(() => mockGetPendingQuotes())
          .thenAnswer((_) async => Right([_quote]));
      when(() => mockGetQuoteById(any()))
          .thenAnswer((_) async => Right(_quote));

      final bloc = _makeBloc(
        getPendingQuotes: mockGetPendingQuotes,
        getQuoteById: mockGetQuoteById,
        initiateSignature: mockInitiateSignature,
        initiateDeposit: mockInitiateDeposit,
        getDocumentSignedUrl: mockGetDocumentSignedUrl,
        getQuoteAttachments: mockGetQuoteAttachments,
        getQuoteAttestation: mockGetQuoteAttestation,
        signQuoteAttestation: mockSignQuoteAttestation,
      );
      bloc.add(const FinancialLoadRequested());

      await tester.pumpWidget(_wrap(bloc));
      await tester.pumpAndSettle();

      bloc.add(const FinancialQuoteSelected('q-1'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('rac0_alternative_banner')), findsNothing);
    });

    testWidgets(
        'affiche le CTA secondaire "Télécharger le devis signé" en état '
        'signed avec documentId (#5243)', (tester) async {
      when(() => mockGetPendingQuotes())
          .thenAnswer((_) async => Right([_signedQuoteWithDocument]));
      when(() => mockGetQuoteById(any()))
          .thenAnswer((_) async => Right(_signedQuoteWithDocument));

      final bloc = _makeBloc(
        getPendingQuotes: mockGetPendingQuotes,
        getQuoteById: mockGetQuoteById,
        initiateSignature: mockInitiateSignature,
        initiateDeposit: mockInitiateDeposit,
        getDocumentSignedUrl: mockGetDocumentSignedUrl,
        getQuoteAttachments: mockGetQuoteAttachments,
        getQuoteAttestation: mockGetQuoteAttestation,
        signQuoteAttestation: mockSignQuoteAttestation,
      );
      bloc.add(const FinancialLoadRequested());

      await tester.pumpWidget(_wrap(bloc));
      await tester.pumpAndSettle();

      bloc.add(const FinancialQuoteSelected('q-signed'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('btn_download')), findsOneWidget);
      expect(find.text('Télécharger le devis signé'), findsOneWidget);
    });

    testWidgets(
        'affiche l\'échéancier acompte/solde daté à la place de "Solde à '
        'régler à la pose" (#5238)', (tester) async {
      when(() => mockGetPendingQuotes())
          .thenAnswer((_) async => Right([_signedQuoteWithDocument]));
      when(() => mockGetQuoteById(any()))
          .thenAnswer((_) async => Right(_signedQuoteWithDocument));

      final bloc = _makeBloc(
        getPendingQuotes: mockGetPendingQuotes,
        getQuoteById: mockGetQuoteById,
        initiateSignature: mockInitiateSignature,
        initiateDeposit: mockInitiateDeposit,
        getDocumentSignedUrl: mockGetDocumentSignedUrl,
        getQuoteAttachments: mockGetQuoteAttachments,
        getQuoteAttestation: mockGetQuoteAttestation,
        signQuoteAttestation: mockSignQuoteAttestation,
      );
      bloc.add(const FinancialLoadRequested());

      await tester.pumpWidget(_wrap(bloc));
      await tester.pumpAndSettle();

      bloc.add(const FinancialQuoteSelected('q-signed'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('payment_schedule')), findsOneWidget);
      expect(find.text('Solde à régler à la pose'), findsNothing);

      final deposit = _signedQuoteWithDocument.depositCents;
      final balance = _signedQuoteWithDocument.patientShareCents - deposit;
      expect(balance + deposit, _signedQuoteWithDocument.patientShareCents);

      expect(
        find.descendant(
          of: find.byKey(const Key('payment_schedule_step_deposit')),
          matching: find.text('Aujourd\'hui · acompte'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('payment_schedule_step_deposit')),
          matching: find.text(formatQuoteCents(deposit)),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('payment_schedule_step_balance')),
          matching: find.text('À la pose · solde'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('payment_schedule_step_balance')),
          matching: find.text(formatQuoteCents(balance)),
        ),
        findsOneWidget,
      );
    });

    testWidgets(
        'appelle GET /v1/payment-schedules et affiche les jalons datés du '
        'praticien à la place de l\'échéancier acompte/solde (#7018)',
        (tester) async {
      when(() => mockGetPendingQuotes())
          .thenAnswer((_) async => Right([_signedQuoteWithDocument]));
      when(() => mockGetQuoteById(any()))
          .thenAnswer((_) async => Right(_signedQuoteWithDocument));

      final mockGetPaymentSchedule = MockGetQuotePaymentScheduleUseCase();
      when(() => mockGetPaymentSchedule(any()))
          .thenAnswer((_) async => Right(_activePaymentSchedule));

      final bloc = _makeBloc(
        getPendingQuotes: mockGetPendingQuotes,
        getQuoteById: mockGetQuoteById,
        initiateSignature: mockInitiateSignature,
        initiateDeposit: mockInitiateDeposit,
        getDocumentSignedUrl: mockGetDocumentSignedUrl,
        getQuoteAttachments: mockGetQuoteAttachments,
        getQuoteAttestation: mockGetQuoteAttestation,
        signQuoteAttestation: mockSignQuoteAttestation,
        getQuotePaymentSchedule: mockGetPaymentSchedule,
      );
      bloc.add(const FinancialLoadRequested());

      await tester.pumpWidget(_wrap(bloc));
      await tester.pumpAndSettle();

      bloc.add(const FinancialQuoteSelected('q-signed'));
      await tester.pumpAndSettle();

      verify(() => mockGetPaymentSchedule('q-signed')).called(1);

      // L'échéancier réel (daté) remplace l'échéancier acompte/solde (#5238)
      // et le CTA « Payer l'acompte » est masqué — l'API le refuserait de
      // toute façon avec 422 (garde #5669) tant que l'échéancier est actif.
      expect(find.byKey(const Key('real_payment_schedule')), findsOneWidget);
      expect(find.byKey(const Key('payment_schedule')), findsNothing);
      expect(find.byKey(const Key('btn_pay')), findsNothing);

      expect(find.text('01/10/2026'), findsOneWidget);
      expect(find.text('01/11/2026'), findsOneWidget);
      expect(find.text('01/12/2026'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('real_payment_schedule_installment_0')),
          matching: find.text(formatQuoteCents(10000)),
        ),
        findsOneWidget,
      );
    });

    testWidgets('n\'affiche pas le CTA de téléchargement sans documentId',
        (tester) async {
      when(() => mockGetPendingQuotes())
          .thenAnswer((_) async => Right([_quote]));
      when(() => mockGetQuoteById(any())).thenAnswer((_) async {
        final signedNoDoc = Quote(
          id: _quote.id,
          cabinetId: _quote.cabinetId,
          practitionerName: _quote.practitionerName,
          items: _quote.items,
          totalCents: _quote.totalCents,
          patientShareCents: _quote.patientShareCents,
          depositCents: _quote.depositCents,
          status: QuoteStatus.signed,
          createdAt: _quote.createdAt,
        );
        return Right(signedNoDoc);
      });

      final bloc = _makeBloc(
        getPendingQuotes: mockGetPendingQuotes,
        getQuoteById: mockGetQuoteById,
        initiateSignature: mockInitiateSignature,
        initiateDeposit: mockInitiateDeposit,
        getDocumentSignedUrl: mockGetDocumentSignedUrl,
        getQuoteAttachments: mockGetQuoteAttachments,
        getQuoteAttestation: mockGetQuoteAttestation,
        signQuoteAttestation: mockSignQuoteAttestation,
      );
      bloc.add(const FinancialLoadRequested());

      await tester.pumpWidget(_wrap(bloc));
      await tester.pumpAndSettle();

      bloc.add(const FinancialQuoteSelected('q-1'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('btn_download')), findsNothing);
    });

    testWidgets(
        'affiche les pièces jointes et verrouille "Signer le devis" tant '
        'que l\'attestation n\'est pas signée (#7201)', (tester) async {
      when(() => mockGetPendingQuotes())
          .thenAnswer((_) async => Right([_quote]));
      when(() => mockGetQuoteById(any()))
          .thenAnswer((_) async => Right(_quote));
      when(() => mockGetQuoteAttachments(any())).thenAnswer((_) async => Right([
            QuoteAttachment(
              id: 'qa-1',
              kind: QuoteAttachmentKind.consent,
              createdAt: DateTime(2026, 6, 1),
            ),
          ]));
      when(() => mockGetQuoteAttestation(any()))
          .thenAnswer((_) async => Right(_pendingAttestation));

      final bloc = _makeBloc(
        getPendingQuotes: mockGetPendingQuotes,
        getQuoteById: mockGetQuoteById,
        initiateSignature: mockInitiateSignature,
        initiateDeposit: mockInitiateDeposit,
        getDocumentSignedUrl: mockGetDocumentSignedUrl,
        getQuoteAttachments: mockGetQuoteAttachments,
        getQuoteAttestation: mockGetQuoteAttestation,
        signQuoteAttestation: mockSignQuoteAttestation,
      );
      bloc.add(const FinancialLoadRequested());

      await tester.pumpWidget(_wrap(bloc));
      await tester.pumpAndSettle();

      bloc.add(const FinancialQuoteSelected('q-1'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('quote_attachments_card')), findsOneWidget);
      expect(find.byKey(const Key('quote_attachment_qa-1')), findsOneWidget);
      expect(find.byKey(const Key('quote_attestation_pending_card')),
          findsOneWidget);
      expect(find.byKey(const Key('btn_sign')), findsNothing);

      // Le bouton "Signer l'attestation" reste désactivé tant que la case
      // "j'ai lu" n'est pas cochée.
      final signAttestationButton = tester
          .widget<NubiaButton>(find.byKey(const Key('btn_sign_attestation')));
      expect(signAttestationButton.onPressed, isNull);

      await tester.ensureVisible(
          find.byKey(const Key('quote_attestation_read_checkbox')));
      await tester
          .tap(find.byKey(const Key('quote_attestation_read_checkbox')));
      await tester.pumpAndSettle();

      final enabledButton = tester
          .widget<NubiaButton>(find.byKey(const Key('btn_sign_attestation')));
      expect(enabledButton.onPressed, isNotNull);
    });

    testWidgets(
        'signer l\'attestation débloque le bouton "Signer le devis" '
        '(#7201)', (tester) async {
      when(() => mockGetPendingQuotes())
          .thenAnswer((_) async => Right([_quote]));
      when(() => mockGetQuoteById(any()))
          .thenAnswer((_) async => Right(_quote));
      when(() => mockGetQuoteAttestation(any()))
          .thenAnswer((_) async => Right(_pendingAttestation));
      when(() => mockSignQuoteAttestation(any()))
          .thenAnswer((_) async => Right(_signedAttestation));

      final bloc = _makeBloc(
        getPendingQuotes: mockGetPendingQuotes,
        getQuoteById: mockGetQuoteById,
        initiateSignature: mockInitiateSignature,
        initiateDeposit: mockInitiateDeposit,
        getDocumentSignedUrl: mockGetDocumentSignedUrl,
        getQuoteAttachments: mockGetQuoteAttachments,
        getQuoteAttestation: mockGetQuoteAttestation,
        signQuoteAttestation: mockSignQuoteAttestation,
      );
      bloc.add(const FinancialLoadRequested());

      await tester.pumpWidget(_wrap(bloc));
      await tester.pumpAndSettle();

      bloc.add(const FinancialQuoteSelected('q-1'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('btn_sign')), findsNothing);

      await tester.ensureVisible(
          find.byKey(const Key('quote_attestation_read_checkbox')));
      await tester
          .tap(find.byKey(const Key('quote_attestation_read_checkbox')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('btn_sign_attestation')));
      await tester.tap(find.byKey(const Key('btn_sign_attestation')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('quote_attestation_signed_card')),
          findsOneWidget);
      expect(find.byKey(const Key('btn_sign')), findsOneWidget);
    });
  });

  group('FinancialBloc', () {
    blocTest<FinancialBloc, FinancialState>(
      'émet [Loading, Loaded(vide)] quand la liste est vide',
      build: () {
        when(() => mockGetPendingQuotes())
            .thenAnswer((_) async => const Right([]));
        return _makeBloc(
          getPendingQuotes: mockGetPendingQuotes,
          getQuoteById: mockGetQuoteById,
          initiateSignature: mockInitiateSignature,
          initiateDeposit: mockInitiateDeposit,
          getDocumentSignedUrl: mockGetDocumentSignedUrl,
          getQuoteAttachments: mockGetQuoteAttachments,
          getQuoteAttestation: mockGetQuoteAttestation,
          signQuoteAttestation: mockSignQuoteAttestation,
        );
      },
      act: (bloc) => bloc.add(const FinancialLoadRequested()),
      expect: () => [
        const FinancialLoading(),
        isA<FinancialLoaded>().having((s) => s.quotes, 'quotes', isEmpty),
      ],
    );

    blocTest<FinancialBloc, FinancialState>(
      'émet [Loading, Loaded] avec un devis',
      build: () {
        when(() => mockGetPendingQuotes())
            .thenAnswer((_) async => Right([_quote]));
        return _makeBloc(
          getPendingQuotes: mockGetPendingQuotes,
          getQuoteById: mockGetQuoteById,
          initiateSignature: mockInitiateSignature,
          initiateDeposit: mockInitiateDeposit,
          getDocumentSignedUrl: mockGetDocumentSignedUrl,
          getQuoteAttachments: mockGetQuoteAttachments,
          getQuoteAttestation: mockGetQuoteAttestation,
          signQuoteAttestation: mockSignQuoteAttestation,
        );
      },
      act: (bloc) => bloc.add(const FinancialLoadRequested()),
      expect: () => [
        const FinancialLoading(),
        isA<FinancialLoaded>()
            .having((s) => s.quotes.length, 'quotes.length', 1),
      ],
    );

    blocTest<FinancialBloc, FinancialState>(
      'émet [Loading, Error] quand getPendingQuotes échoue',
      build: () {
        when(() => mockGetPendingQuotes()).thenAnswer(
            (_) async => const Left(NetworkFailure('Erreur réseau.')));
        return _makeBloc(
          getPendingQuotes: mockGetPendingQuotes,
          getQuoteById: mockGetQuoteById,
          initiateSignature: mockInitiateSignature,
          initiateDeposit: mockInitiateDeposit,
          getDocumentSignedUrl: mockGetDocumentSignedUrl,
          getQuoteAttachments: mockGetQuoteAttachments,
          getQuoteAttestation: mockGetQuoteAttestation,
          signQuoteAttestation: mockSignQuoteAttestation,
        );
      },
      act: (bloc) => bloc.add(const FinancialLoadRequested()),
      expect: () => [
        const FinancialLoading(),
        isA<FinancialError>()
            .having((s) => s.message, 'message', 'Erreur réseau.'),
      ],
    );

    blocTest<FinancialBloc, FinancialState>(
      'émet [Loading, QuoteDetail] quand un devis est sélectionné',
      build: () {
        when(() => mockGetQuoteById(any()))
            .thenAnswer((_) async => Right(_quote));
        return _makeBloc(
          getPendingQuotes: mockGetPendingQuotes,
          getQuoteById: mockGetQuoteById,
          initiateSignature: mockInitiateSignature,
          initiateDeposit: mockInitiateDeposit,
          getDocumentSignedUrl: mockGetDocumentSignedUrl,
          getQuoteAttachments: mockGetQuoteAttachments,
          getQuoteAttestation: mockGetQuoteAttestation,
          signQuoteAttestation: mockSignQuoteAttestation,
        );
      },
      seed: () => FinancialLoaded([_quote]),
      act: (bloc) => bloc.add(const FinancialQuoteSelected('q-1')),
      expect: () => [
        const FinancialLoading(),
        isA<FinancialQuoteDetail>()
            .having((s) => s.quote.id, 'quote.id', 'q-1'),
      ],
    );

    blocTest<FinancialBloc, FinancialState>(
      'émet [QuoteDetail(signed)] quand la signature est lancée (#3705 : '
      'synchrone, pas de redirection à attendre)',
      build: () {
        final signedQuote = Quote(
          id: _quote.id,
          cabinetId: _quote.cabinetId,
          practitionerName: _quote.practitionerName,
          items: _quote.items,
          totalCents: _quote.totalCents,
          patientShareCents: _quote.patientShareCents,
          depositCents: _quote.depositCents,
          status: QuoteStatus.signed,
          createdAt: _quote.createdAt,
        );
        when(() => mockInitiateSignature(any()))
            .thenAnswer((_) async => Right(signedQuote));
        return _makeBloc(
          getPendingQuotes: mockGetPendingQuotes,
          getQuoteById: mockGetQuoteById,
          initiateSignature: mockInitiateSignature,
          initiateDeposit: mockInitiateDeposit,
          getDocumentSignedUrl: mockGetDocumentSignedUrl,
          getQuoteAttachments: mockGetQuoteAttachments,
          getQuoteAttestation: mockGetQuoteAttestation,
          signQuoteAttestation: mockSignQuoteAttestation,
        );
      },
      seed: () => FinancialQuoteDetail(quote: _quote, quotes: [_quote]),
      act: (bloc) => bloc.add(const FinancialSignatureRequested()),
      expect: () => [
        isA<FinancialQuoteDetail>()
            .having((s) => s.quote.status, 'quote.status', QuoteStatus.signed),
      ],
    );

    blocTest<FinancialBloc, FinancialState>(
      // #7270 : le retour depuis un lien profond (détail seul, sans liste
      // dans l'état courant) doit RECHARGER les devis en attente plutôt que
      // de réémettre la liste (vide) transportée par l'état de détail.
      'émet [Loading, Loaded] avec la liste rechargée quand BackToList est '
      'reçu depuis le détail',
      build: () {
        when(() => mockGetPendingQuotes())
            .thenAnswer((_) async => Right([_quote]));
        return _makeBloc(
          getPendingQuotes: mockGetPendingQuotes,
          getQuoteById: mockGetQuoteById,
          initiateSignature: mockInitiateSignature,
          initiateDeposit: mockInitiateDeposit,
          getDocumentSignedUrl: mockGetDocumentSignedUrl,
          getQuoteAttachments: mockGetQuoteAttachments,
          getQuoteAttestation: mockGetQuoteAttestation,
          signQuoteAttestation: mockSignQuoteAttestation,
        );
      },
      seed: () => FinancialQuoteDetail(quote: _quote, quotes: const []),
      act: (bloc) => bloc.add(const FinancialBackToList()),
      expect: () => [
        const FinancialLoading(),
        isA<FinancialLoaded>()
            .having((s) => s.quotes.length, 'quotes.length', 1),
      ],
      verify: (_) {
        verify(() => mockGetPendingQuotes()).called(1);
      },
    );

    blocTest<FinancialBloc, FinancialState>(
      'émet [QuoteDetail(documentUrl)] quand le téléchargement est demandé '
      '(#5243)',
      build: () {
        when(() => mockGetDocumentSignedUrl(any()))
            .thenAnswer((_) async => const Right('https://vault/doc-1'));
        return _makeBloc(
          getPendingQuotes: mockGetPendingQuotes,
          getQuoteById: mockGetQuoteById,
          initiateSignature: mockInitiateSignature,
          initiateDeposit: mockInitiateDeposit,
          getDocumentSignedUrl: mockGetDocumentSignedUrl,
          getQuoteAttachments: mockGetQuoteAttachments,
          getQuoteAttestation: mockGetQuoteAttestation,
          signQuoteAttestation: mockSignQuoteAttestation,
        );
      },
      seed: () => FinancialQuoteDetail(
        quote: _signedQuoteWithDocument,
        quotes: [_signedQuoteWithDocument],
      ),
      act: (bloc) => bloc.add(const FinancialDownloadRequested()),
      expect: () => [
        isA<FinancialQuoteDetail>()
            .having((s) => s.documentUrl, 'documentUrl', 'https://vault/doc-1'),
      ],
      verify: (_) {
        verify(() => mockGetDocumentSignedUrl('doc-1')).called(1);
      },
    );

    blocTest<FinancialBloc, FinancialState>(
      'émet [QuoteDetail(pièces jointes + attestation)] quand '
      'AttestationLoadRequested est reçu (#7201)',
      build: () {
        when(() => mockGetQuoteAttachments(any()))
            .thenAnswer((_) async => Right([
                  QuoteAttachment(
                    id: 'qa-1',
                    kind: QuoteAttachmentKind.consent,
                    createdAt: DateTime(2026, 6, 1),
                  ),
                ]));
        when(() => mockGetQuoteAttestation(any()))
            .thenAnswer((_) async => Right(_pendingAttestation));
        return _makeBloc(
          getPendingQuotes: mockGetPendingQuotes,
          getQuoteById: mockGetQuoteById,
          initiateSignature: mockInitiateSignature,
          initiateDeposit: mockInitiateDeposit,
          getDocumentSignedUrl: mockGetDocumentSignedUrl,
          getQuoteAttachments: mockGetQuoteAttachments,
          getQuoteAttestation: mockGetQuoteAttestation,
          signQuoteAttestation: mockSignQuoteAttestation,
        );
      },
      seed: () => FinancialQuoteDetail(quote: _quote, quotes: [_quote]),
      act: (bloc) => bloc.add(const FinancialAttestationLoadRequested()),
      expect: () => [
        isA<FinancialQuoteDetail>()
            .having((s) => s.attachments.length, 'attachments.length', 1)
            .having((s) => s.attestation, 'attestation', _pendingAttestation),
      ],
    );

    blocTest<FinancialBloc, FinancialState>(
      'émet [QuoteDetail(attestation signée)] quand '
      'AttestationSignRequested est reçu (#7201)',
      build: () {
        when(() => mockSignQuoteAttestation(any()))
            .thenAnswer((_) async => Right(_signedAttestation));
        return _makeBloc(
          getPendingQuotes: mockGetPendingQuotes,
          getQuoteById: mockGetQuoteById,
          initiateSignature: mockInitiateSignature,
          initiateDeposit: mockInitiateDeposit,
          getDocumentSignedUrl: mockGetDocumentSignedUrl,
          getQuoteAttachments: mockGetQuoteAttachments,
          getQuoteAttestation: mockGetQuoteAttestation,
          signQuoteAttestation: mockSignQuoteAttestation,
        );
      },
      seed: () => FinancialQuoteDetail(
        quote: _quote,
        quotes: [_quote],
        attestation: _pendingAttestation,
      ),
      act: (bloc) => bloc.add(const FinancialAttestationSignRequested()),
      expect: () => [
        isA<FinancialQuoteDetail>().having(
            (s) => s.attestation?.isSigned, 'attestation.isSigned', true),
      ],
      verify: (_) {
        verify(() => mockSignQuoteAttestation('q-1')).called(1);
      },
    );
  });
}

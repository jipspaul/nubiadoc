import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart' hide State;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_practicien/features/devis/devis_bloc.dart';
import 'package:app_practicien/features/devis/devis_event.dart';
import 'package:app_practicien/features/devis/devis_page.dart';
import 'package:app_practicien/features/devis/devis_state.dart';
import 'package:app_practicien/features/devis/invoice_reminder_cubit.dart';
import 'package:app_practicien/features/devis/quote_documents_cubit.dart';
import 'package:app_practicien/features/devis/quote_events_cubit.dart';
import 'package:app_practicien/features/devis/widgets/quote_timeline.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class MockListCabinetQuotesUseCase extends Mock
    implements ListCabinetQuotesUseCase {}

class MockGetCabinetQuoteUseCase extends Mock
    implements GetCabinetQuoteUseCase {}

class MockSendCabinetQuoteUseCase extends Mock
    implements SendCabinetQuoteUseCase {}

class MockDevisBloc extends MockBloc<DevisEvent, DevisState>
    implements DevisBloc {}

class MockInvoiceReminderRepository extends Mock
    implements InvoiceReminderRepository {}

class MockQuoteAttachmentsRepository extends Mock
    implements QuoteAttachmentsRepository {}

class MockQuoteAttestationRepository extends Mock
    implements QuoteAttestationRepository {}

class MockPatientDocumentsRepository extends Mock
    implements PatientDocumentsRepository {}

class MockLetterTemplatesRepository extends Mock
    implements LetterTemplatesRepository {}

class MockConsentTemplateRepository extends Mock
    implements ConsentTemplateRepository {}

class MockQuoteEventsCubit extends MockCubit<QuoteEventsState>
    implements QuoteEventsCubit {}

/// `QuoteTimeline` (#7175, parité secrétariat #7467) exige un
/// `QuoteEventsCubit` dans son contexte — enregistré dans GetIt (même
/// découpage que `QuoteDocumentsCubit` ci-dessous). `events` vide par
/// défaut : dégrade vers le comportement historique (seule « Devis créé »/
/// « Signature attendue » dérivées de `CabinetQuote`).
MockQuoteEventsCubit _registerQuoteEventsCubit({
  List<QuoteEvent> events = const [],
}) {
  final cubit = MockQuoteEventsCubit();
  when(() => cubit.state).thenReturn(QuoteEventsLoaded(events: events));
  when(() => cubit.load(any())).thenAnswer((_) async {});
  GetIt.instance.registerFactory<QuoteEventsCubit>(() => cubit);
  return cubit;
}

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

const _line = QuoteLineItem(
  id: 'l1',
  label: 'Couronne céramique',
  ccamCode: 'HBLD038',
  toothLabel: '26',
  totalCents: 60000,
  amoShareCents: 8400,
  amcShareCents: 20000,
  patientShareCents: 31600,
);

final _draftQuote = CabinetQuote(
  id: 'q1',
  quoteRef: 'q1',
  cabinetId: 'cab-1',
  patientId: 'pat-1',
  patientName: 'Jean Dupont',
  totalCents: 60000,
  patientShareCents: 31600,
  status: CabinetQuoteStatus.draft,
  createdAt: DateTime(2026, 6, 20),
  items: const [_line],
);

final _sentQuote = CabinetQuote(
  id: 'q2',
  quoteRef: 'q2',
  cabinetId: 'cab-1',
  patientId: 'pat-2',
  patientName: 'Marie Martin',
  totalCents: 120000,
  patientShareCents: 50000,
  status: CabinetQuoteStatus.sent,
  createdAt: DateTime(2026, 6, 21),
);

final _overdueQuote = CabinetQuote(
  id: 'q3',
  quoteRef: 'q3',
  cabinetId: 'cab-1',
  patientId: 'pat-3',
  patientName: 'Paul Impaye',
  totalCents: 60000,
  patientShareCents: 31600,
  status: CabinetQuoteStatus.signed,
  createdAt: DateTime(2026, 6, 20),
  signedAt: DateTime(2026, 5, 1),
  isOverdue: true,
);

DevisBloc _makeBloc({
  required MockListCabinetQuotesUseCase list,
  required MockGetCabinetQuoteUseCase getById,
  MockSendCabinetQuoteUseCase? send,
}) =>
    DevisBloc(
      list: list,
      getById: getById,
      send: send ?? MockSendCabinetQuoteUseCase(),
    );

Widget _wrap(DevisBloc bloc) => MaterialApp(
      theme: NubiaTheme.light,
      home: Scaffold(
        body: BlocProvider<DevisBloc>.value(
          value: bloc,
          child: const DevisBody(),
        ),
      ),
    );

// ---------------------------------------------------------------------------

void main() {
  late MockListCabinetQuotesUseCase mockList;
  late MockGetCabinetQuoteUseCase mockGet;
  late MockQuoteAttachmentsRepository attachmentsRepo;
  late MockQuoteAttestationRepository attestationRepo;
  late MockPatientDocumentsRepository patientDocumentsRepo;
  late MockLetterTemplatesRepository letterTemplatesRepo;
  late MockConsentTemplateRepository consentTemplateRepo;

  // `QuoteDocumentsSection` (#7202/#7203) est rendue pour tout devis en
  // détail : son `BlocProvider<QuoteDocumentsCubit>` doit donc être
  // enregistré pour TOUS les tests du fichier, pas seulement ceux qui la
  // ciblent — sinon `GetIt.instance<QuoteDocumentsCubit>()` explose dès le
  // premier `pumpWidget` sur `DevisDetailLoaded`.
  setUp(() {
    mockList = MockListCabinetQuotesUseCase();
    mockGet = MockGetCabinetQuoteUseCase();

    attachmentsRepo = MockQuoteAttachmentsRepository();
    attestationRepo = MockQuoteAttestationRepository();
    patientDocumentsRepo = MockPatientDocumentsRepository();
    letterTemplatesRepo = MockLetterTemplatesRepository();
    consentTemplateRepo = MockConsentTemplateRepository();

    when(() => attachmentsRepo.list(any()))
        .thenAnswer((_) async => const Right([]));
    when(() => attestationRepo.get(any()))
        .thenAnswer((_) async => const Right(null));
    when(() =>
            patientDocumentsRepo.list(any(), category: any(named: 'category')))
        .thenAnswer((_) async => const Right([]));
    when(() => letterTemplatesRepo.list())
        .thenAnswer((_) async => const Right([]));
    when(() => consentTemplateRepo.list())
        .thenAnswer((_) async => const Right([]));

    GetIt.instance.registerFactory<QuoteDocumentsCubit>(
      () => QuoteDocumentsCubit(
        listAttachments: ListQuoteAttachmentsUseCase(attachmentsRepo),
        createAttachment: CreateQuoteAttachmentUseCase(attachmentsRepo),
        deleteAttachment: DeleteQuoteAttachmentUseCase(attachmentsRepo),
        getAttestation: GetQuoteAttestationUseCase(attestationRepo),
        createAttestation: CreateQuoteAttestationUseCase(attestationRepo),
        listPatientDocuments: ListPatientDocumentsUseCase(patientDocumentsRepo),
        listLetterTemplates: ListLetterTemplatesUseCase(letterTemplatesRepo),
        listConsentTemplates: ListConsentTemplatesUseCase(consentTemplateRepo),
        renderConsentTemplate:
            RenderConsentTemplateUseCase(consentTemplateRepo),
      ),
    );
    _registerQuoteEventsCubit();
    addTearDown(GetIt.instance.reset);
  });

  group('DevisBloc', () {
    blocTest<DevisBloc, DevisState>(
      'émet Loading puis ListLoaded après chargement réussi',
      build: () {
        when(() => mockList(page: any(named: 'page')))
            .thenAnswer((_) async => Right([_draftQuote, _sentQuote]));
        return _makeBloc(list: mockList, getById: mockGet);
      },
      act: (bloc) => bloc.add(const DevisListRequested()),
      expect: () => [
        const DevisLoading(),
        DevisListLoaded([_draftQuote, _sentQuote]),
      ],
    );

    blocTest<DevisBloc, DevisState>(
      'émet Loading puis Error si le chargement échoue',
      build: () {
        when(() => mockList(page: any(named: 'page')))
            .thenAnswer((_) async => Left(NetworkFailure('Pas de réseau')));
        return _makeBloc(list: mockList, getById: mockGet);
      },
      act: (bloc) => bloc.add(const DevisListRequested()),
      expect: () => [
        const DevisLoading(),
        const DevisError('Pas de réseau'),
      ],
    );

    blocTest<DevisBloc, DevisState>(
      'émet Loading puis DetailLoaded à la sélection d\'un devis',
      build: () {
        when(() => mockGet(any())).thenAnswer((_) async => Right(_draftQuote));
        return _makeBloc(list: mockList, getById: mockGet);
      },
      act: (bloc) => bloc.add(const DevisQuoteSelected('q1')),
      expect: () => [
        const DevisLoading(),
        DevisDetailLoaded(_draftQuote),
      ],
    );

    blocTest<DevisBloc, DevisState>(
      'appelle l\'endpoint puis émet SendInProgress → Sent (statut serveur)',
      build: () {
        final mockSend = MockSendCabinetQuoteUseCase();
        when(() => mockSend(any()))
            .thenAnswer((_) async => const Right(CabinetQuoteStatus.sent));
        return _makeBloc(list: mockList, getById: mockGet, send: mockSend);
      },
      seed: () => DevisDetailLoaded(_draftQuote),
      act: (bloc) => bloc.add(const DevisSendRequested('q1')),
      expect: () => [
        DevisSendInProgress(_draftQuote),
        isA<DevisSent>().having(
          (s) => s.quote.status,
          'status',
          CabinetQuoteStatus.sent,
        ),
      ],
    );

    blocTest<DevisBloc, DevisState>(
      'émet SendInProgress puis SendFailure si l\'envoi échoue',
      build: () {
        final mockSend = MockSendCabinetQuoteUseCase();
        when(() => mockSend(any())).thenAnswer((_) async => Left(ServerFailure(
              message: 'Envoi impossible.',
            )));
        return _makeBloc(list: mockList, getById: mockGet, send: mockSend);
      },
      seed: () => DevisDetailLoaded(_draftQuote),
      act: (bloc) => bloc.add(const DevisSendRequested('q1')),
      expect: () => [
        DevisSendInProgress(_draftQuote),
        isA<DevisSendFailure>(),
      ],
    );

    // #6672 — le CTA « Générer le devis de la phase N » du plan de
    // traitement ouvrait la liste des devis de TOUT le cabinet (autres
    // patients compris) au lieu de rester scopé au patient du plan ouvert.
    blocTest<DevisBloc, DevisState>(
      'DevisListRequested(patientId: ...) filtre la liste sur ce patient',
      build: () {
        when(() => mockList(patientId: any(named: 'patientId')))
            .thenAnswer((_) async => Right([_draftQuote]));
        return _makeBloc(list: mockList, getById: mockGet);
      },
      act: (bloc) => bloc.add(const DevisListRequested(patientId: 'pat-1')),
      expect: () => [
        const DevisLoading(),
        DevisListLoaded([_draftQuote]),
      ],
      verify: (_) {
        verify(() => mockList(patientId: 'pat-1')).called(1);
      },
    );
  });

  group('DevisBody (widget)', () {
    testWidgets('affiche le skeleton en chargement', (tester) async {
      final bloc = MockDevisBloc();
      when(() => bloc.state).thenReturn(const DevisLoading());
      await tester.pumpWidget(_wrap(bloc));
      expect(find.byKey(const Key('devis_loading')), findsOneWidget);
    });

    testWidgets('affiche la liste des devis', (tester) async {
      final bloc = MockDevisBloc();
      when(() => bloc.state)
          .thenReturn(DevisListLoaded([_draftQuote, _sentQuote]));
      await tester.pumpWidget(_wrap(bloc));
      expect(find.byKey(const Key('devis_list')), findsOneWidget);
      expect(find.byKey(const Key('devis_item_q1')), findsOneWidget);
      expect(find.text('Jean Dupont'), findsOneWidget);
    });

    testWidgets('affiche l\'état vide', (tester) async {
      final bloc = MockDevisBloc();
      when(() => bloc.state).thenReturn(const DevisListLoaded([]));
      await tester.pumpWidget(_wrap(bloc));
      expect(find.byKey(const Key('devis_empty')), findsOneWidget);
    });

    testWidgets('affiche l\'erreur avec retry', (tester) async {
      final bloc = MockDevisBloc();
      when(() => bloc.state).thenReturn(const DevisError('Boom'));
      await tester.pumpWidget(_wrap(bloc));
      expect(find.byKey(const Key('devis_error')), findsOneWidget);
    });

    testWidgets('affiche le détail avec CTA Envoyer pour un brouillon',
        (tester) async {
      final bloc = MockDevisBloc();
      when(() => bloc.state).thenReturn(DevisDetailLoaded(_draftQuote));
      await tester.pumpWidget(_wrap(bloc));
      expect(find.byKey(const Key('devis_detail')), findsOneWidget);
      expect(find.byType(AmountHeader), findsOneWidget);
      expect(find.byType(QuoteCard), findsOneWidget);
      expect(find.byKey(const Key('btn_send_devis')), findsOneWidget);
    });

    testWidgets('affiche la ventilation Part AMO / Part AMC par ligne (#4063)',
        (tester) async {
      final bloc = MockDevisBloc();
      when(() => bloc.state).thenReturn(DevisDetailLoaded(_draftQuote));
      await tester.pumpWidget(_wrap(bloc));
      // _line : amoShareCents=8400 (84 €), amcShareCents=20000 (200 €).
      expect(find.textContaining('Part AMO : 84 €'), findsOneWidget);
      expect(find.textContaining('Part AMC : 200 €'), findsOneWidget);
    });

    testWidgets('masque le CTA Envoyer pour un devis déjà envoyé',
        (tester) async {
      final bloc = MockDevisBloc();
      when(() => bloc.state).thenReturn(DevisDetailLoaded(_sentQuote));
      await tester.pumpWidget(_wrap(bloc));
      expect(find.byKey(const Key('devis_detail')), findsOneWidget);
      expect(find.byKey(const Key('btn_send_devis')), findsNothing);
    });

    testWidgets('le CTA Envoyer dispatch DevisSendRequested', (tester) async {
      final bloc = MockDevisBloc();
      when(() => bloc.state).thenReturn(DevisDetailLoaded(_draftQuote));
      await tester.pumpWidget(_wrap(bloc));
      await tester.tap(find.byKey(const Key('btn_send_devis')));
      verify(() => bloc.add(const DevisSendRequested('q1'))).called(1);
    });

    testWidgets('affiche la confirmation d\'envoi', (tester) async {
      final bloc = MockDevisBloc();
      when(() => bloc.state).thenReturn(DevisSent(_sentQuote));
      await tester.pumpWidget(_wrap(bloc));
      expect(find.byKey(const Key('devis_sent')), findsOneWidget);
    });
  });

  // --- Bouton « Relancer le patient » (#7205) ---------------------------------
  group('DevisBody — relance facture échue (#7205)', () {
    late MockInvoiceReminderRepository reminderRepo;

    setUp(() {
      reminderRepo = MockInvoiceReminderRepository();
      GetIt.instance.registerFactory<InvoiceReminderCubit>(
        () => InvoiceReminderCubit(
          listReminders: ListInvoiceRemindersUseCase(reminderRepo),
          sendReminder: SendInvoiceReminderUseCase(reminderRepo),
        ),
      );
      addTearDown(GetIt.instance.reset);
    });

    testWidgets('facture non échue : aucun bouton « Relancer le patient »',
        (tester) async {
      final bloc = MockDevisBloc();
      when(() => bloc.state).thenReturn(DevisDetailLoaded(_sentQuote));
      await tester.pumpWidget(_wrap(bloc));
      await tester.pump();
      expect(find.byKey(const Key('btn_relancer_patient')), findsNothing);
    });

    testWidgets('facture échue : bouton visible + historique vide par défaut',
        (tester) async {
      when(() => reminderRepo.listHistory('q3'))
          .thenAnswer((_) async => const Right([]));
      final bloc = MockDevisBloc();
      when(() => bloc.state).thenReturn(DevisDetailLoaded(_overdueQuote));
      await tester.pumpWidget(_wrap(bloc));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('btn_relancer_patient')), findsOneWidget);
      expect(
        find.byKey(const Key('invoice_reminder_history_empty')),
        findsOneWidget,
      );
    });

    testWidgets(
        'tap sur « Relancer le patient » envoie la relance puis recharge '
        'l\'historique', (tester) async {
      when(() => reminderRepo.listHistory('q3'))
          .thenAnswer((_) async => const Right([]));
      when(() => reminderRepo.send('q3')).thenAnswer((_) async {
        when(() => reminderRepo.listHistory('q3')).thenAnswer(
          (_) async => Right([
            InvoiceReminder(
              channel: InvoiceReminderChannel.push,
              sentAt: DateTime(2026, 8, 1, 9, 30),
            ),
          ]),
        );
        return const Right(null);
      });
      final bloc = MockDevisBloc();
      when(() => bloc.state).thenReturn(DevisDetailLoaded(_overdueQuote));
      await tester.pumpWidget(_wrap(bloc));
      await tester.pumpAndSettle();

      // Le panneau « documents à joindre » (#7202/#7203) ajouté au-dessus
      // pousse ce bouton sous la surface de test visible.
      await tester.ensureVisible(find.byKey(const Key('btn_relancer_patient')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('btn_relancer_patient')));
      await tester.pumpAndSettle();

      verify(() => reminderRepo.send('q3')).called(1);
      expect(
        find.byKey(const Key('invoice_reminder_history_list')),
        findsOneWidget,
      );
      expect(find.text('Notification'), findsOneWidget);
    });
  });

  group('DevisPage', () {
    setUp(() {
      GetIt.instance.registerFactory<DevisBloc>(
        () => _makeBloc(list: mockList, getById: mockGet),
      );
      addTearDown(GetIt.instance.reset);
    });

    // #6672 — la route `/devis` reçoit désormais `?patientId=` depuis le CTA
    // contextuel du plan de traitement : la liste chargée par `DevisPage`
    // doit rester scopée à ce patient plutôt que de tomber sur le cabinet
    // entier.
    testWidgets(
        'patientId fourni → scope la liste initiale à ce patient plutôt '
        'qu\'au cabinet entier', (tester) async {
      when(() => mockList(patientId: any(named: 'patientId')))
          .thenAnswer((_) async => Right([_draftQuote]));

      await tester.pumpWidget(MaterialApp(
        theme: NubiaTheme.light,
        home: const Scaffold(body: DevisPage(patientId: 'pat-1')),
      ));
      await tester.pumpAndSettle();

      verify(() => mockList(patientId: 'pat-1')).called(1);
    });
  });

  // --- Documents à joindre + attestation d'information (#7202/#7203) -------
  group('QuoteDocumentsSection', () {
    testWidgets('affiche les pièces jointes déjà déposées', (tester) async {
      when(() => attachmentsRepo.list('q1')).thenAnswer((_) async => Right([
            QuoteAttachment(
              id: 'a1',
              kind: QuoteAttachmentKind.consent,
              documentId: 'doc1',
              createdAt: DateTime(2026, 6, 20),
            ),
          ]));
      when(() => patientDocumentsRepo.list('pat-1', category: 'consentement'))
          .thenAnswer((_) async => Right([
                PatientDocument(
                  id: 'doc1',
                  category: 'consentement',
                  filename: 'Consentement extraction.pdf',
                  mimeType: 'application/pdf',
                  sizeBytes: 1024,
                  createdAt: DateTime(2026, 6, 1),
                ),
              ]));
      final bloc = MockDevisBloc();
      when(() => bloc.state).thenReturn(DevisDetailLoaded(_draftQuote));
      await tester.pumpWidget(_wrap(bloc));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('quote_attachment_a1')), findsOneWidget);
      expect(find.text('Consentement extraction.pdf'), findsOneWidget);
    });

    testWidgets('ajoute un consentement en pièce jointe', (tester) async {
      when(() => patientDocumentsRepo.list('pat-1', category: 'consentement'))
          .thenAnswer((_) async => Right([
                PatientDocument(
                  id: 'doc1',
                  category: 'consentement',
                  filename: 'Consentement extraction.pdf',
                  mimeType: 'application/pdf',
                  sizeBytes: 1024,
                  createdAt: DateTime(2026, 6, 1),
                ),
              ]));
      when(() => attachmentsRepo.create(
            'q1',
            kind: QuoteAttachmentKind.consent,
            documentId: 'doc1',
            templateRef: null,
          )).thenAnswer((_) async {
        final created = QuoteAttachment(
          id: 'a1',
          kind: QuoteAttachmentKind.consent,
          documentId: 'doc1',
          createdAt: DateTime(2026, 6, 20),
        );
        when(() => attachmentsRepo.list('q1'))
            .thenAnswer((_) async => Right([created]));
        return Right(created);
      });
      final bloc = MockDevisBloc();
      when(() => bloc.state).thenReturn(DevisDetailLoaded(_draftQuote));
      await tester.pumpWidget(_wrap(bloc));
      await tester.pumpAndSettle();

      await tester
          .ensureVisible(find.byKey(const Key('quote_documents_add_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('quote_documents_add_button')));
      await tester.pumpAndSettle();
      await tester
          .tap(find.byKey(const Key('add_quote_attachment_kind_consent')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('add_quote_attachment_item_doc1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('add_quote_attachment_confirm')));
      await tester.pumpAndSettle();

      verify(() => attachmentsRepo.create(
            'q1',
            kind: QuoteAttachmentKind.consent,
            documentId: 'doc1',
            templateRef: null,
          )).called(1);
      expect(find.byKey(const Key('quote_attachment_a1')), findsOneWidget);
    });

    // #7198 — sélection d'un modèle de consentement depuis le devis : le
    // modèle est rendu pour ce devis (document généré), puis attaché.
    testWidgets('génère et attache un consentement depuis un modèle',
        (tester) async {
      when(() => consentTemplateRepo.list()).thenAnswer((_) async => Right([
            ConsentTemplate(
              id: 'tpl1',
              actCategory: 'implantologie',
              title: 'Consentement implant',
              bodyMarkdown: 'Texte du modèle',
              version: 1,
              isGlobal: true,
              createdAt: DateTime(2026, 1, 1),
            ),
          ]));
      when(() => consentTemplateRepo.render('tpl1', quoteId: 'q1')).thenAnswer(
        (_) async => const Right(RenderedConsentTemplate(
          documentId: 'doc-rendered',
          filename: 'consentement-implantologie-doc-rendered.pdf',
          sizeBytes: 512,
          body: 'Texte rendu',
        )),
      );
      when(() => attachmentsRepo.create(
            'q1',
            kind: QuoteAttachmentKind.consent,
            documentId: 'doc-rendered',
            templateRef: null,
          )).thenAnswer((_) async {
        final created = QuoteAttachment(
          id: 'a2',
          kind: QuoteAttachmentKind.consent,
          documentId: 'doc-rendered',
          createdAt: DateTime(2026, 6, 20),
        );
        when(() => attachmentsRepo.list('q1'))
            .thenAnswer((_) async => Right([created]));
        return Right(created);
      });
      final bloc = MockDevisBloc();
      when(() => bloc.state).thenReturn(DevisDetailLoaded(_draftQuote));
      await tester.pumpWidget(_wrap(bloc));
      await tester.pumpAndSettle();

      await tester
          .ensureVisible(find.byKey(const Key('quote_documents_add_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('quote_documents_add_button')));
      await tester.pumpAndSettle();
      await tester
          .tap(find.byKey(const Key('add_quote_attachment_kind_consent')));
      await tester.pumpAndSettle();
      await tester
          .tap(find.byKey(const Key('add_quote_attachment_template_tpl1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('add_quote_attachment_confirm')));
      await tester.pumpAndSettle();

      verify(() => consentTemplateRepo.render('tpl1', quoteId: 'q1'))
          .called(1);
      verify(() => attachmentsRepo.create(
            'q1',
            kind: QuoteAttachmentKind.consent,
            documentId: 'doc-rendered',
            templateRef: null,
          )).called(1);
      expect(find.byKey(const Key('quote_attachment_a2')), findsOneWidget);
    });

    testWidgets('retire une pièce jointe', (tester) async {
      when(() => attachmentsRepo.list('q1')).thenAnswer((_) async => Right([
            QuoteAttachment(
              id: 'a1',
              kind: QuoteAttachmentKind.consent,
              documentId: 'doc1',
              createdAt: DateTime(2026, 6, 20),
            ),
          ]));
      when(() => attachmentsRepo.delete('q1', 'a1')).thenAnswer((_) async {
        when(() => attachmentsRepo.list('q1'))
            .thenAnswer((_) async => const Right([]));
        return const Right(null);
      });
      final bloc = MockDevisBloc();
      when(() => bloc.state).thenReturn(DevisDetailLoaded(_draftQuote));
      await tester.pumpWidget(_wrap(bloc));
      await tester.pumpAndSettle();

      await tester
          .ensureVisible(find.byKey(const Key('quote_attachment_remove_a1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('quote_attachment_remove_a1')));
      await tester.pumpAndSettle();

      verify(() => attachmentsRepo.delete('q1', 'a1')).called(1);
      expect(find.byKey(const Key('quote_attachments_empty')), findsOneWidget);
    });

    testWidgets('génère une attestation d\'information', (tester) async {
      when(() => attestationRepo.create('q1', body: 'Texte informatif'))
          .thenAnswer((_) async => Right(QuoteAttestation(
                id: 'att1',
                body: 'Texte informatif',
                createdAt: DateTime(2026, 6, 20),
              )));
      final bloc = MockDevisBloc();
      when(() => bloc.state).thenReturn(DevisDetailLoaded(_draftQuote));
      await tester.pumpWidget(_wrap(bloc));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('quote_attestation_status_none')),
          findsOneWidget);

      await tester.ensureVisible(
          find.byKey(const Key('quote_attestation_generate_button')));
      await tester.pumpAndSettle();
      await tester
          .tap(find.byKey(const Key('quote_attestation_generate_button')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('quote_attestation_body_field')),
        'Texte informatif',
      );
      await tester.tap(find.byKey(const Key('quote_attestation_confirm')));
      await tester.pumpAndSettle();

      verify(() => attestationRepo.create('q1', body: 'Texte informatif'))
          .called(1);
      expect(find.byKey(const Key('quote_attestation_status_pending')),
          findsOneWidget);
    });

    testWidgets('affiche une attestation déjà signée', (tester) async {
      when(() => attestationRepo.get('q1')).thenAnswer((_) async => Right(
            QuoteAttestation(
              id: 'att1',
              body: 'Texte informatif',
              signedAt: DateTime(2026, 6, 25),
              createdAt: DateTime(2026, 6, 20),
            ),
          ));
      final bloc = MockDevisBloc();
      when(() => bloc.state).thenReturn(DevisDetailLoaded(_draftQuote));
      await tester.pumpWidget(_wrap(bloc));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('quote_attestation_status_signed')),
          findsOneWidget);
      expect(find.textContaining('Signée le 25/06/2026'), findsOneWidget);
    });
  });

  group('QuoteTimeline (#7175)', () {
    setUp(() async {
      // Le `setUp` global du fichier a déjà enregistré un `QuoteEventsCubit`
      // (pour `_DetailView`) — on repart d'un GetIt vierge pour que
      // `_registerQuoteEventsCubit` (appelé par `buildTimeline`) ne heurte
      // pas un double enregistrement.
      await GetIt.instance.reset();
      addTearDown(GetIt.instance.reset);
    });

    Widget buildTimeline(
      CabinetQuote quote, {
      DateTime? now,
      List<QuoteEvent> events = const [],
    }) {
      final cubit = _registerQuoteEventsCubit(events: events);
      return MaterialApp(
        theme: NubiaTheme.light,
        home: Scaffold(
          body: BlocProvider<QuoteEventsCubit>.value(
            value: cubit,
            child: QuoteTimeline(quote: quote, now: now),
          ),
        ),
      );
    }

    testWidgets(
        'devis brouillon sans expiresAt : seule « Devis créé » est affichée',
        (tester) async {
      await tester.pumpWidget(buildTimeline(_draftQuote));
      await tester.pumpAndSettle();

      expect(find.text('Devis créé'), findsOneWidget);
      expect(find.text('Signature attendue'), findsNothing);
    });

    testWidgets(
        'devis envoyé + consulté (journal quote_event) affiche les étapes '
        'correspondantes', (tester) async {
      final events = [
        QuoteEvent(kind: QuoteEventKind.sent, at: DateTime(2026, 6, 21, 9)),
        QuoteEvent(kind: QuoteEventKind.viewed, at: DateTime(2026, 6, 22, 10)),
      ];
      await tester.pumpWidget(buildTimeline(_sentQuote, events: events));
      await tester.pumpAndSettle();

      expect(find.text('Devis créé'), findsOneWidget);
      expect(find.text('Envoyé au patient'), findsOneWidget);
      expect(find.text('Consulté par le patient'), findsOneWidget);
    });

    testWidgets('devis signé (événement `signed`) affiche « Signé » et plus '
        '« Signature attendue »', (tester) async {
      final signedQuote = CabinetQuote(
        id: 'q4',
        quoteRef: 'q4',
        cabinetId: 'cab-1',
        patientId: 'pat-4',
        patientName: 'Sophie Signée',
        totalCents: 60000,
        patientShareCents: 31600,
        status: CabinetQuoteStatus.signed,
        createdAt: DateTime(2026, 6, 20),
        expiresAt: DateTime(2026, 7, 20),
      );
      final events = [
        QuoteEvent(kind: QuoteEventKind.sent, at: DateTime(2026, 6, 21, 9)),
        QuoteEvent(kind: QuoteEventKind.signed, at: DateTime(2026, 6, 23, 11)),
      ];
      await tester.pumpWidget(buildTimeline(signedQuote, events: events));
      await tester.pumpAndSettle();

      expect(find.text('Signé'), findsOneWidget);
      expect(find.text('Signature attendue'), findsNothing);
    });
  });
}

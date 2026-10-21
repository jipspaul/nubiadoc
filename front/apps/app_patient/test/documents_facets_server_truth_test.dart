// Issue #8318 — régression de #8297 (pagination à la demande) : les
// facettes de catégorie et leur compteur étaient calculés sur la seule
// page chargée en mémoire (20 documents) au lieu du coffre-fort entier
// (745 documents), faisant mentir l'en-tête (« 745 documents ») et la puce
// « Tous » (« 20 ») côte à côte, et masquant toute catégorie absente de la
// première page. Les facettes doivent refléter l'état serveur
// (DocumentsLoaded.total / categoryCounts), indépendamment du nombre de
// documents déjà chargés.
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_patient/features/documents/documents_bloc.dart';
import 'package:app_patient/features/documents/documents_event.dart';
import 'package:app_patient/features/documents/documents_page.dart';
import 'package:app_patient/features/documents/documents_state.dart';

class _MockDocumentsBloc extends MockBloc<DocumentsEvent, DocumentsState>
    implements DocumentsBloc {}

void main() {
  setUpAll(() {
    registerFallbackValue(const DocumentsLoadRequested());
  });

  late _MockDocumentsBloc mockBloc;

  setUp(() async {
    mockBloc = _MockDocumentsBloc();
    await GetIt.instance.reset();
    GetIt.instance.registerFactory<DocumentsBloc>(() => mockBloc);
  });

  tearDown(() async => GetIt.instance.reset());

  testWidgets(
      'puces de facette et en-tête reflètent le volume serveur, pas la '
      'seule page chargée', (tester) async {
    // Une seule page chargée (20 docs, tous "ordonnance") mais un coffre-
    // fort de 745 documents répartis sur plusieurs catégories (vérité
    // serveur de la repro #8318).
    final loadedPage = List.generate(
      20,
      (i) => Document(
        id: 'doc-$i',
        name: 'Ordonnance $i.pdf',
        category: DocumentCategory.prescription,
        createdAt: DateTime(2026, 1, 1),
        fileSizeBytes: 1024,
        mimeType: 'application/pdf',
      ),
    );

    whenListen(
      mockBloc,
      const Stream<DocumentsState>.empty(),
      initialState: DocumentsLoaded(
        loadedPage,
        total: 745,
        hasMore: true,
        categoryCounts: const {
          DocumentCategory.prescription: 443,
          DocumentCategory.quote: 112,
          DocumentCategory.invoice: 51,
          DocumentCategory.mutualCard: 31,
          DocumentCategory.xray: 28,
          DocumentCategory.instructions: 24,
          DocumentCategory.photo: 12,
          DocumentCategory.report: 8,
          DocumentCategory.consent: 8,
          DocumentCategory.cbct: 3,
        },
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: NubiaTheme.light,
        home: const Scaffold(body: DocumentsPage()),
      ),
    );
    await tester.pumpAndSettle();

    // En-tête : volume RÉEL du coffre-fort, pas les 20 documents chargés.
    expect(find.text('745 documents · 0 ajouté cette semaine'), findsOneWidget);

    // Puce « Tous » : même vérité que l'en-tête — jamais le nombre de
    // documents déjà chargés en mémoire.
    expect(find.text('Tous 745'), findsOneWidget);

    // Catégories réellement présentes sur le coffre-fort entier, avec leur
    // compteur serveur — y compris des catégories absentes de la page
    // chargée (ex. Devis, Facture : aucun des 20 docs chargés n'en fait
    // partie, mais elles ont bien une puce avec le bon compteur).
    expect(find.text('Ordonnance 443'), findsOneWidget);
    expect(find.text('Devis 112'), findsOneWidget);
    expect(find.text('Facture 51'), findsOneWidget);
    expect(find.text('Carte mutuelle 31'), findsOneWidget);
    expect(find.text('Radio 28'), findsOneWidget);
    expect(find.text('Consigne 24'), findsOneWidget);
    expect(find.text('Photo 12'), findsOneWidget);
    expect(find.text('Compte-rendu 8'), findsOneWidget);
    expect(find.text('Consentement 8'), findsOneWidget);
    expect(find.text('CBCT 3'), findsOneWidget);

    // Reliquat (courrier/dmsm, ni mappés ni comptés individuellement) :
    // 745 - (443+112+51+31+28+24+12+8+8+3) = 25, affiché sous « Autre ».
    expect(find.text('Autre 25'), findsOneWidget);

    // Catégorie absente du coffre entier (compteur serveur nul) : aucune
    // puce « Carte vitale » affichée.
    expect(find.text('Carte vitale 0'), findsNothing);
  });
}

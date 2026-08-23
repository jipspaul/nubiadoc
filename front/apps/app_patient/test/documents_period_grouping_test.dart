// Issue #5217 — la liste plate de documents ne donnait aucun point
// d'ancrage pour chercher un document médical. Les cartes sont désormais
// regroupées sous des en-têtes de période dérivés de `createdAt` :
// « Cette semaine » (7 derniers jours) précède les groupes mensuels
// « Mois AAAA », eux-mêmes triés du plus récent au plus ancien, chacun
// affichant son compteur « N documents » à droite (maquette design-v2,
// point 1).
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

const _monthsFr = [
  'Janvier',
  'Février',
  'Mars',
  'Avril',
  'Mai',
  'Juin',
  'Juillet',
  'Août',
  'Septembre',
  'Octobre',
  'Novembre',
  'Décembre',
];

Document _doc(String id, DateTime createdAt) => Document(
      id: id,
      name: '$id.pdf',
      category: DocumentCategory.prescription,
      createdAt: createdAt,
      fileSizeBytes: 1024,
      mimeType: 'application/pdf',
    );

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

  Future<void> pump(WidgetTester tester, List<Document> docs) async {
    whenListen(
      mockBloc,
      Stream<DocumentsState>.fromIterable([DocumentsLoaded(docs)])
          .asBroadcastStream(),
      initialState: DocumentsLoaded(docs),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: NubiaTheme.light,
        home: const Scaffold(body: DocumentsPage()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
      'groupe « Cette semaine » précède les groupes mensuels décroissants, '
      'chacun avec son compteur', (tester) async {
    final now = DateTime.now();
    final recent1 = now.subtract(const Duration(days: 1));
    final recent2 = now.subtract(const Duration(days: 3));
    final monthAgo = DateTime(now.year, now.month - 1, 15);
    final twoMonthsAgo = DateTime(now.year, now.month - 2, 15);

    final monthAgoKey = Key('doc_group_${monthAgo.year}_${monthAgo.month}');
    final twoMonthsAgoKey =
        Key('doc_group_${twoMonthsAgo.year}_${twoMonthsAgo.month}');
    final monthAgoLabel = '${_monthsFr[monthAgo.month - 1]} ${monthAgo.year}';
    final twoMonthsAgoLabel =
        '${_monthsFr[twoMonthsAgo.month - 1]} ${twoMonthsAgo.year}';

    await pump(tester, [
      _doc('r1', recent1),
      _doc('r2', recent2),
      _doc('m1', monthAgo),
      _doc('o1', twoMonthsAgo),
    ]);

    // Les trois en-têtes sont présents.
    expect(find.byKey(const Key('doc_group_this_week')), findsOneWidget);
    expect(find.byKey(monthAgoKey), findsOneWidget);
    expect(find.byKey(twoMonthsAgoKey), findsOneWidget);

    // Compteurs par groupe : « Cette semaine » a 2 documents, chaque mois 1.
    expect(
      find.descendant(
        of: find.byKey(const Key('doc_group_this_week')),
        matching: find.text('2 documents'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(monthAgoKey),
        matching: find.text('1 document'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(twoMonthsAgoKey),
        matching: find.text('1 document'),
      ),
      findsOneWidget,
    );

    // Libellés mensuels « Mois AAAA », affichés en capitales.
    expect(
      find.descendant(
        of: find.byKey(monthAgoKey),
        matching: find.text(monthAgoLabel.toUpperCase()),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(twoMonthsAgoKey),
        matching: find.text(twoMonthsAgoLabel.toUpperCase()),
      ),
      findsOneWidget,
    );

    // Ordre vertical : Cette semaine, puis mois du plus récent au plus
    // ancien.
    final thisWeekY =
        tester.getTopLeft(find.byKey(const Key('doc_group_this_week'))).dy;
    final monthAgoY = tester.getTopLeft(find.byKey(monthAgoKey)).dy;
    final twoMonthsAgoY = tester.getTopLeft(find.byKey(twoMonthsAgoKey)).dy;

    expect(thisWeekY, lessThan(monthAgoY));
    expect(monthAgoY, lessThan(twoMonthsAgoY));

    // Les cartes documents restent bien présentes sous leur groupe.
    expect(find.byKey(const Key('document_r1')), findsOneWidget);
    expect(find.byKey(const Key('document_r2')), findsOneWidget);
    expect(find.byKey(const Key('document_m1')), findsOneWidget);
    expect(find.byKey(const Key('document_o1')), findsOneWidget);
  });
}

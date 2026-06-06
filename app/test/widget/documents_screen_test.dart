import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_patient/domain/entities/document.dart';
import 'package:nubia_patient/presentation/features/documents/bloc/document_bloc.dart';
import 'package:nubia_patient/presentation/features/documents/bloc/document_event.dart';
import 'package:nubia_patient/presentation/features/documents/bloc/document_state.dart';
import 'package:nubia_patient/presentation/features/documents/widgets/document_category_tabs.dart';
import 'package:nubia_patient/presentation/features/documents/widgets/document_list_tile.dart';
import 'package:nubia_patient/presentation/theme/nubia_theme.dart';

class MockDocumentBloc extends MockBloc<DocumentEvent, DocumentState>
    implements DocumentBloc {}

Document _makeDoc(String id, DocumentCategory category) => Document(
      id: id,
      name: 'Document $id',
      category: category,
      createdAt: DateTime(2026, 1, 15),
      fileSizeBytes: 102400,
      mimeType: 'application/pdf',
    );

const _categories = [
  null,
  DocumentCategory.quote,
  DocumentCategory.invoice,
  DocumentCategory.prescription,
  DocumentCategory.xray,
];

Widget _wrap(DocumentBloc bloc) {
  return MaterialApp(
    theme: NubiaTheme.light,
    home: BlocProvider<DocumentBloc>.value(
      value: bloc,
      child: const _DocumentsBodyUnwrapped(),
    ),
  );
}

/// Reproduit le body de DocumentsScreen sans le BlocProvider+DI pour
/// pouvoir injecter un mock directement dans les tests.
class _DocumentsBodyUnwrapped extends StatelessWidget {
  const _DocumentsBodyUnwrapped();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mes documents')),
      body: BlocBuilder<DocumentBloc, DocumentState>(
        builder: (context, state) {
          if (state is DocumentLoading || state is DocumentInitial) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state is DocumentError) {
            return Center(child: Text(state.message));
          }
          if (state is DocumentLoaded) {
            final docs = state.filtered;
            return Column(
              children: [
                DocumentCategoryTabs(
                  categories: _categories,
                  selected: state.selectedCategory,
                  onSelected: (cat) => context.read<DocumentBloc>().add(
                        DocumentCategorySelected(cat),
                      ),
                ),
                Expanded(
                  child: docs.isEmpty
                      ? const Center(child: Text('Aucun document'))
                      : ListView.separated(
                          itemCount: docs.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final doc = docs[index];
                            return DocumentListTile(
                              document: doc,
                              onTap: () {},
                              onDownload: () {},
                            );
                          },
                        ),
                ),
              ],
            );
          }
          return const SizedBox.shrink();
        },
      ),
    );
  }
}

void main() {
  late MockDocumentBloc bloc;

  setUp(() {
    bloc = MockDocumentBloc();
  });

  tearDown(() => bloc.close());

  testWidgets('affiche un indicateur de chargement en état Loading',
      (tester) async {
    when(() => bloc.state).thenReturn(const DocumentLoading());

    await tester.pumpWidget(_wrap(bloc));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('affiche un message d\'erreur en état Error', (tester) async {
    when(() => bloc.state)
        .thenReturn(const DocumentError('Erreur réseau.'));

    await tester.pumpWidget(_wrap(bloc));

    expect(find.text('Erreur réseau.'), findsOneWidget);
  });

  testWidgets('affiche les onglets de catégories en état Loaded',
      (tester) async {
    final docs = [
      _makeDoc('d1', DocumentCategory.quote),
      _makeDoc('d2', DocumentCategory.invoice),
    ];
    when(() => bloc.state).thenReturn(DocumentLoaded(docs));

    await tester.pumpWidget(_wrap(bloc));

    // Tous les onglets sont présents
    expect(find.byType(DocumentCategoryTabs), findsOneWidget);
    expect(find.text('Tous'), findsOneWidget);
    expect(find.text('Devis'), findsOneWidget);
    expect(find.text('Factures'), findsOneWidget);
    expect(find.text('Ordonnances'), findsOneWidget);
    expect(find.text('Radios'), findsOneWidget);
  });

  testWidgets('affiche la liste des documents en état Loaded', (tester) async {
    final docs = [
      _makeDoc('d1', DocumentCategory.quote),
      _makeDoc('d2', DocumentCategory.invoice),
    ];
    when(() => bloc.state).thenReturn(DocumentLoaded(docs));

    await tester.pumpWidget(_wrap(bloc));

    expect(find.byType(DocumentListTile), findsNWidgets(2));
    expect(find.text('Document d1'), findsOneWidget);
    expect(find.text('Document d2'), findsOneWidget);
  });

  testWidgets('affiche vide quand aucun document dans la catégorie sélectionnée',
      (tester) async {
    final docs = [_makeDoc('d1', DocumentCategory.quote)];
    when(() => bloc.state).thenReturn(
      DocumentLoaded(docs, selectedCategory: DocumentCategory.invoice),
    );

    await tester.pumpWidget(_wrap(bloc));

    expect(find.text('Aucun document'), findsOneWidget);
    expect(find.byType(DocumentListTile), findsNothing);
  });
}

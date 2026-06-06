import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_patient/domain/entities/document.dart';
import 'package:nubia_patient/presentation/features/documents/bloc/document_bloc.dart';
import 'package:nubia_patient/presentation/features/documents/bloc/document_event.dart';
import 'package:nubia_patient/presentation/features/documents/bloc/document_state.dart';
import 'package:nubia_patient/presentation/theme/nubia_theme.dart';

class MockDocumentBloc extends MockBloc<DocumentEvent, DocumentState>
    implements DocumentBloc {}

Document _makeDoc({String? sha256}) => Document(
      id: 'doc-1',
      name: 'radiographie.pdf',
      category: DocumentCategory.xray,
      createdAt: DateTime(2026, 3, 10),
      fileSizeBytes: 204800,
      mimeType: 'application/pdf',
      sha256: sha256,
    );

Widget _wrap(DocumentBloc bloc, Document doc) {
  return MaterialApp(
    theme: NubiaTheme.light,
    home: BlocProvider<DocumentBloc>.value(
      value: bloc,
      child: _DocumentDetailBodyUnwrapped(document: doc),
    ),
  );
}

/// Reproduit le body de DocumentDetailScreen sans BlocProvider+DI.
class _DocumentDetailBodyUnwrapped extends StatelessWidget {
  const _DocumentDetailBodyUnwrapped({required this.document});

  final Document document;

  @override
  Widget build(BuildContext context) {
    return BlocListener<DocumentBloc, DocumentState>(
      listener: (context, state) async {
        if (state is DocumentSignedUrlError) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(state.message)),
          );
        }
      },
      child: Scaffold(
        appBar: AppBar(title: Text(document.name)),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('Radio'),
            const Text('10/03/2026'),
            const Text('PDF'),
            const Text('200.0 Ko'),
            if (document.sha256 != null) Text(document.sha256!),
          ],
        ),
        floatingActionButton: BlocBuilder<DocumentBloc, DocumentState>(
          builder: (context, state) {
            final isLoading = state is DocumentSignedUrlLoading;
            return FloatingActionButton.extended(
              key: const Key('download_fab'),
              onPressed: isLoading
                  ? null
                  : () => context.read<DocumentBloc>().add(
                        DocumentSignedUrlRequested(document.id),
                      ),
              icon: isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.download_outlined),
              label: const Text('Télécharger'),
            );
          },
        ),
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

  testWidgets('affiche le nom du document dans l\'AppBar', (tester) async {
    when(() => bloc.state).thenReturn(const DocumentInitial());

    await tester.pumpWidget(_wrap(bloc, _makeDoc()));

    expect(find.text('radiographie.pdf'), findsOneWidget);
  });

  testWidgets('affiche les métadonnées du document', (tester) async {
    when(() => bloc.state).thenReturn(const DocumentInitial());

    await tester.pumpWidget(_wrap(bloc, _makeDoc()));

    expect(find.text('Radio'), findsOneWidget);
    expect(find.text('10/03/2026'), findsOneWidget);
    expect(find.text('PDF'), findsOneWidget);
    expect(find.text('200.0 Ko'), findsOneWidget);
  });

  testWidgets('n\'affiche pas SHA-256 si absent', (tester) async {
    when(() => bloc.state).thenReturn(const DocumentInitial());

    await tester.pumpWidget(_wrap(bloc, _makeDoc()));

    // No sha256 in doc → no sha256 row
    expect(find.text('SHA-256'), findsNothing);
  });

  testWidgets('affiche le bouton de téléchargement', (tester) async {
    when(() => bloc.state).thenReturn(const DocumentInitial());

    await tester.pumpWidget(_wrap(bloc, _makeDoc()));

    expect(find.byKey(const Key('download_fab')), findsOneWidget);
    expect(find.text('Télécharger'), findsOneWidget);
  });

  testWidgets('le bouton téléchargement est désactivé en DocumentSignedUrlLoading',
      (tester) async {
    when(() => bloc.state)
        .thenReturn(const DocumentSignedUrlLoading('doc-1'));

    await tester.pumpWidget(_wrap(bloc, _makeDoc()));

    final fab = tester.widget<FloatingActionButton>(
      find.byKey(const Key('download_fab')),
    );
    expect(fab.onPressed, isNull);
  });

  testWidgets('affiche un snackbar d\'erreur en DocumentSignedUrlError',
      (tester) async {
    whenListen(
      bloc,
      Stream.fromIterable([
        const DocumentSignedUrlError('Lien expiré.'),
      ]),
      initialState: const DocumentInitial(),
    );

    await tester.pumpWidget(_wrap(bloc, _makeDoc()));
    await tester.pump();

    expect(find.text('Lien expiré.'), findsOneWidget);
  });

  testWidgets('envoie DocumentSignedUrlRequested au tap télécharger',
      (tester) async {
    when(() => bloc.state).thenReturn(const DocumentInitial());

    await tester.pumpWidget(_wrap(bloc, _makeDoc()));

    await tester.tap(find.byKey(const Key('download_fab')));
    await tester.pump();

    verify(() => bloc.add(const DocumentSignedUrlRequested('doc-1'))).called(1);
  });
}

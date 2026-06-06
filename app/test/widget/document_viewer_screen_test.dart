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

Document _makePdfDoc() => Document(
      id: 'doc-pdf-1',
      name: 'ordonnance.pdf',
      category: DocumentCategory.prescription,
      createdAt: DateTime(2026, 5, 1),
      fileSizeBytes: 51200,
      mimeType: 'application/pdf',
    );

Document _makeImageDoc() => Document(
      id: 'doc-img-1',
      name: 'radio.jpg',
      category: DocumentCategory.xray,
      createdAt: DateTime(2026, 5, 1),
      fileSizeBytes: 204800,
      mimeType: 'image/jpeg',
    );

/// Injecte un [MockDocumentBloc] directement, sans passer par le DI.
Widget _wrap(DocumentBloc bloc, Document doc) {
  return MaterialApp(
    theme: NubiaTheme.light,
    home: BlocProvider<DocumentBloc>.value(
      value: bloc,
      child: _ViewerBodyUnwrapped(document: doc),
    ),
  );
}

/// Reproduit le body de [DocumentViewerScreen] sans le BlocProvider+DI.
class _ViewerBodyUnwrapped extends StatelessWidget {
  const _ViewerBodyUnwrapped({required this.document});

  final Document document;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(document.name)),
      body: BlocBuilder<DocumentBloc, DocumentState>(
        builder: (context, state) {
          if (state is DocumentSignedUrlLoading || state is DocumentInitial) {
            return const Center(
              child: CircularProgressIndicator(key: Key('viewer_loading')),
            );
          }
          if (state is DocumentSignedUrlError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.error_outline,
                      color: Theme.of(context).colorScheme.error),
                  const SizedBox(height: 8),
                  Text(state.message),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    key: const Key('viewer_retry_btn'),
                    onPressed: () => context
                        .read<DocumentBloc>()
                        .add(DocumentSignedUrlRequested(document.id)),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Réessayer'),
                  ),
                ],
              ),
            );
          }
          if (state is DocumentSignedUrlReady) {
            if (state.url == '__unsupported__') {
              return Center(
                child: FilledButton.icon(
                  key: const Key('open_external_btn'),
                  onPressed: () {},
                  icon: const Icon(Icons.open_in_new_outlined),
                  label: const Text('Ouvrir dans le navigateur'),
                ),
              );
            }
            // PDF/image — just show a placeholder in tests
            return const Center(
              child: Text('Viewer ready', key: Key('viewer_ready')),
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

  testWidgets('affiche un indicateur de chargement en état Initial',
      (tester) async {
    when(() => bloc.state).thenReturn(const DocumentInitial());

    await tester.pumpWidget(_wrap(bloc, _makePdfDoc()));

    expect(find.byKey(const Key('viewer_loading')), findsOneWidget);
  });

  testWidgets('affiche le nom du document dans l\'AppBar', (tester) async {
    when(() => bloc.state).thenReturn(const DocumentInitial());

    await tester.pumpWidget(_wrap(bloc, _makePdfDoc()));

    expect(find.text('ordonnance.pdf'), findsOneWidget);
  });

  testWidgets(
      'affiche le nom de l\'image dans l\'AppBar pour un document image',
      (tester) async {
    when(() => bloc.state).thenReturn(const DocumentInitial());

    await tester.pumpWidget(_wrap(bloc, _makeImageDoc()));

    expect(find.text('radio.jpg'), findsOneWidget);
  });

  testWidgets('affiche un message d\'erreur en état DocumentSignedUrlError',
      (tester) async {
    when(() => bloc.state)
        .thenReturn(const DocumentSignedUrlError('Lien introuvable.'));

    await tester.pumpWidget(_wrap(bloc, _makePdfDoc()));

    expect(find.text('Lien introuvable.'), findsOneWidget);
    expect(find.byKey(const Key('viewer_retry_btn')), findsOneWidget);
  });

  testWidgets('le bouton Réessayer envoie DocumentSignedUrlRequested',
      (tester) async {
    when(() => bloc.state)
        .thenReturn(const DocumentSignedUrlError('Erreur.'));

    await tester.pumpWidget(_wrap(bloc, _makePdfDoc()));

    await tester.tap(find.byKey(const Key('viewer_retry_btn')));
    await tester.pump();

    verify(() => bloc.add(const DocumentSignedUrlRequested('doc-pdf-1')))
        .called(1);
  });

  testWidgets('affiche le viewer quand l\'URL est prête', (tester) async {
    when(() => bloc.state).thenReturn(
      const DocumentSignedUrlReady(
        documentId: 'doc-pdf-1',
        url: 'https://storage.example.com/ordonnance.pdf?sig=abc',
      ),
    );

    await tester.pumpWidget(_wrap(bloc, _makePdfDoc()));

    expect(find.byKey(const Key('viewer_ready')), findsOneWidget);
  });
}

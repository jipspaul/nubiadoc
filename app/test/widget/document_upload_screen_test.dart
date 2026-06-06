import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_patient/core/utils/file_picker_service.dart';
import 'package:nubia_patient/domain/entities/document.dart';
import 'package:nubia_patient/presentation/features/documents/bloc/document_bloc.dart';
import 'package:nubia_patient/presentation/features/documents/bloc/document_event.dart';
import 'package:nubia_patient/presentation/features/documents/bloc/document_state.dart';
import 'package:nubia_patient/presentation/features/documents/widgets/document_category_selector.dart';
import 'package:nubia_patient/presentation/features/documents/widgets/document_file_picker_button.dart';
import 'package:nubia_patient/presentation/theme/nubia_theme.dart';

class MockDocumentBloc extends MockBloc<DocumentEvent, DocumentState>
    implements DocumentBloc {}

/// Stub file picker that immediately returns a fixed [PickedFile].
class _StubFilePicker extends FilePickerService {
  const _StubFilePicker();

  @override
  Future<PickedFile?> pickFile() async => const PickedFile(
        path: '/tmp/test.pdf',
        name: 'test.pdf',
        mimeType: 'application/pdf',
      );
}

Document _makeDoc(String id) => Document(
      id: id,
      name: 'doc-$id.pdf',
      category: DocumentCategory.other,
      createdAt: DateTime(2026, 1, 15),
      fileSizeBytes: 1024,
      mimeType: 'application/pdf',
    );

Widget _wrap(DocumentBloc bloc) {
  return MaterialApp(
    theme: NubiaTheme.light,
    home: BlocProvider<DocumentBloc>.value(
      value: bloc,
      child: const _UploadBodyUnwrapped(),
    ),
  );
}

/// Reproduit le body de DocumentUploadScreen sans BlocProvider+DI pour
/// pouvoir injecter un mock directement dans les tests.
///
/// Utilise un [_StubFilePicker] pour éviter les canaux platform natifs.
class _UploadBodyUnwrapped extends StatefulWidget {
  const _UploadBodyUnwrapped();

  @override
  State<_UploadBodyUnwrapped> createState() => _UploadBodyUnwrappedState();
}

class _UploadBodyUnwrappedState extends State<_UploadBodyUnwrapped> {
  DocumentCategory _selectedCategory = DocumentCategory.other;
  String? _filePath;
  String? _filename;
  String? _mimeType;

  void _onFileSelected({
    required String path,
    required String name,
    required String mime,
  }) {
    setState(() {
      _filePath = path;
      _filename = name;
      _mimeType = mime;
    });
  }

  void _submit() {
    final path = _filePath;
    final name = _filename;
    final mime = _mimeType;
    if (path == null || name == null || mime == null) return;
    context.read<DocumentBloc>().add(
          DocumentUploadRequested(
            filePath: path,
            filename: name,
            mimeType: mime,
            category: _selectedCategory,
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<DocumentBloc, DocumentState>(
      listener: (context, state) {
        if (state is DocumentUploadSuccess) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Document envoyé avec succès.')),
          );
        }
        if (state is DocumentUploadFailure) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(state.message)),
          );
        }
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Envoyer un document')),
        body: BlocBuilder<DocumentBloc, DocumentState>(
          builder: (context, state) {
            final isUploading = state is DocumentUploading;
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                DocumentCategorySelector(
                  selected: _selectedCategory,
                  onChanged: (cat) => setState(() => _selectedCategory = cat),
                ),
                const SizedBox(height: 24),
                DocumentFilePickerButton(
                  filename: _filename,
                  onFileSelected: _onFileSelected,
                  pickerService: const _StubFilePicker(),
                ),
                const SizedBox(height: 32),
                FilledButton(
                  key: const Key('upload_submit'),
                  onPressed: _filePath != null && !isUploading ? _submit : null,
                  child: isUploading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Envoyer'),
                ),
              ],
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

  testWidgets('affiche le sélecteur de catégorie et le bouton de fichier',
      (tester) async {
    when(() => bloc.state).thenReturn(const DocumentInitial());

    await tester.pumpWidget(_wrap(bloc));

    expect(find.byType(DocumentCategorySelector), findsOneWidget);
    expect(find.byType(DocumentFilePickerButton), findsOneWidget);
    expect(find.byKey(const Key('upload_submit')), findsOneWidget);
  });

  testWidgets('le bouton Envoyer est désactivé sans fichier sélectionné',
      (tester) async {
    when(() => bloc.state).thenReturn(const DocumentInitial());

    await tester.pumpWidget(_wrap(bloc));

    final button = tester.widget<FilledButton>(
      find.byKey(const Key('upload_submit')),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('le bouton Envoyer s\'active après sélection d\'un fichier',
      (tester) async {
    when(() => bloc.state).thenReturn(const DocumentInitial());

    await tester.pumpWidget(_wrap(bloc));

    // Tap the file picker button (stub returns a file immediately).
    await tester.tap(find.byKey(const Key('file_picker_button')));
    await tester.pump();

    final button = tester.widget<FilledButton>(
      find.byKey(const Key('upload_submit')),
    );
    expect(button.onPressed, isNotNull);
    expect(find.text('test.pdf'), findsOneWidget);
  });

  testWidgets('affiche un indicateur de chargement en état DocumentUploading',
      (tester) async {
    when(() => bloc.state).thenReturn(const DocumentUploading());

    await tester.pumpWidget(_wrap(bloc));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('envoie DocumentUploadRequested lors du tap sur Envoyer',
      (tester) async {
    when(() => bloc.state).thenReturn(const DocumentInitial());

    await tester.pumpWidget(_wrap(bloc));

    // Select a file via stub picker.
    await tester.tap(find.byKey(const Key('file_picker_button')));
    await tester.pump();

    // Tap submit.
    await tester.tap(find.byKey(const Key('upload_submit')));
    await tester.pump();

    verify(() => bloc.add(const DocumentUploadRequested(
          filePath: '/tmp/test.pdf',
          filename: 'test.pdf',
          mimeType: 'application/pdf',
          category: DocumentCategory.other,
        ))).called(1);
  });

  testWidgets('affiche un snackbar d\'erreur en état DocumentUploadFailure',
      (tester) async {
    whenListen(
      bloc,
      Stream.fromIterable([
        const DocumentUploadFailure('Erreur serveur.'),
      ]),
      initialState: const DocumentInitial(),
    );

    await tester.pumpWidget(_wrap(bloc));
    await tester.pump();

    expect(find.text('Erreur serveur.'), findsOneWidget);
  });

  testWidgets('affiche un snackbar de succès en état DocumentUploadSuccess',
      (tester) async {
    whenListen(
      bloc,
      Stream.fromIterable([
        DocumentUploadSuccess(_makeDoc('d1')),
      ]),
      initialState: const DocumentInitial(),
    );

    await tester.pumpWidget(_wrap(bloc));
    await tester.pump();

    expect(find.text('Document envoyé avec succès.'), findsOneWidget);
  });
}

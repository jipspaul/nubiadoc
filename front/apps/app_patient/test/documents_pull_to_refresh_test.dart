import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
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

  final doc = Document(
    id: 'doc-1',
    name: 'Ordonnance.pdf',
    category: DocumentCategory.prescription,
    createdAt: DateTime(2026, 1, 1),
    fileSizeBytes: 10240,
    mimeType: 'application/pdf',
  );

  late _MockDocumentsBloc mockBloc;

  setUp(() async {
    mockBloc = _MockDocumentsBloc();
    await GetIt.instance.reset();
    GetIt.instance.registerFactory<DocumentsBloc>(() => mockBloc);
  });

  tearDown(() async => GetIt.instance.reset());

  testWidgets('pull-to-refresh dispatch DocumentsLoadRequested',
      (tester) async {
    whenListen(
      mockBloc,
      Stream<DocumentsState>.fromIterable([
        DocumentsLoaded([doc])
      ]).asBroadcastStream(),
      initialState: DocumentsLoaded([doc]),
    );

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: DocumentsPage())),
    );
    await tester.pumpAndSettle();

    clearInteractions(mockBloc);

    await tester.drag(
      find.byKey(const ValueKey('documents_refresh')),
      const Offset(0, 400),
    );
    await tester.pumpAndSettle();

    verify(
      () => mockBloc.add(any(that: isA<DocumentsLoadRequested>())),
    ).called(1);
  });
}

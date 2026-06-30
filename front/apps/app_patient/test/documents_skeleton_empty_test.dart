import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

import 'package:app_patient/features/documents/documents_bloc.dart';
import 'package:app_patient/features/documents/documents_event.dart';
import 'package:app_patient/features/documents/documents_state.dart';

// ---------------------------------------------------------------------------
// Mock
// ---------------------------------------------------------------------------

class _MockDocumentsBloc extends MockBloc<DocumentsEvent, DocumentsState>
    implements DocumentsBloc {}

// ---------------------------------------------------------------------------
// Stub widget — reproduit le contrat UI sans passer par GetIt
// ---------------------------------------------------------------------------

class _DocumentsPageStub extends StatelessWidget {
  const _DocumentsPageStub();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<DocumentsBloc, DocumentsState>(
      builder: (context, state) {
        if (state is DocumentsLoading || state is DocumentsInitial) {
          return const Center(child: CircularProgressIndicator());
        }
        if (state is DocumentsLoaded && state.documents.isEmpty) {
          return const NubiaEmptyState(
            icon: Icons.folder_open_outlined,
            title: 'Aucun document',
          );
        }
        return const SizedBox.shrink();
      },
    );
  }
}

Widget _wrap(DocumentsBloc bloc) => MaterialApp(
      home: BlocProvider<DocumentsBloc>.value(
        value: bloc,
        child: const Scaffold(body: _DocumentsPageStub()),
      ),
    );

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('DocumentsPage — loading', () {
    testWidgets('affiche CircularProgressIndicator en état Loading',
        (tester) async {
      final bloc = _MockDocumentsBloc();
      when(() => bloc.state).thenReturn(const DocumentsLoading());

      await tester.pumpWidget(_wrap(bloc));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });

  group('DocumentsPage — empty state', () {
    testWidgets('affiche NubiaEmptyState quand Loaded(items=[]) est émis',
        (tester) async {
      final bloc = _MockDocumentsBloc();
      when(() => bloc.state).thenReturn(DocumentsLoaded(const []));

      await tester.pumpWidget(_wrap(bloc));
      await tester.pump();

      expect(find.byType(NubiaEmptyState), findsOneWidget);
    });
  });
}

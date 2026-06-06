import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_patient/presentation/features/documents/pages/document_sign_screen.dart';
import 'package:nubia_patient/presentation/features/signature/bloc/signature_bloc.dart';
import 'package:nubia_patient/presentation/features/signature/bloc/signature_event.dart';
import 'package:nubia_patient/presentation/features/signature/bloc/signature_state.dart';

class MockSignatureBloc extends MockBloc<SignatureEvent, SignatureState>
    implements SignatureBloc {}

Widget _wrap(SignatureBloc bloc) {
  return MaterialApp(
    home: BlocProvider<SignatureBloc>.value(
      value: bloc,
      child: const DocumentSignScreen(id: 'doc-42'),
    ),
  );
}

void main() {
  late MockSignatureBloc bloc;

  setUp(() {
    bloc = MockSignatureBloc();
  });

  tearDown(() => bloc.close());

  testWidgets(
    'DocumentSignScreen affiche le statut en attente (SignaturePending)',
    (tester) async {
      when(() => bloc.state).thenReturn(const SignaturePending());

      await tester.pumpWidget(_wrap(bloc));

      // Le corps en attente affiche le titre et le bouton de signature.
      expect(find.text('Signature électronique'), findsOneWidget);
      expect(find.byKey(const Key('sign_button')), findsOneWidget);
    },
  );

  testWidgets(
    'DocumentSignScreen affiche "Signature en cours…" en état SignatureInProgress',
    (tester) async {
      when(() => bloc.state).thenReturn(const SignatureInProgress());

      await tester.pumpWidget(_wrap(bloc));

      expect(find.text('Signature en cours…'), findsOneWidget);
    },
  );

  testWidgets(
    'DocumentSignScreen affiche "Document signé" en état SignatureSigned',
    (tester) async {
      when(() => bloc.state).thenReturn(const SignatureSigned());

      await tester.pumpWidget(_wrap(bloc));

      expect(find.text('Document signé avec succès.'), findsOneWidget);
    },
  );
}

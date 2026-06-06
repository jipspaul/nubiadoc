import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_patient/domain/entities/patient_account.dart';
import 'package:nubia_patient/domain/repositories/account_repository.dart';
import 'package:nubia_patient/presentation/features/coverage/bloc/coverage_bloc.dart';
import 'package:nubia_patient/presentation/features/coverage/bloc/coverage_event.dart';
import 'package:nubia_patient/presentation/features/coverage/bloc/coverage_state.dart';
import 'package:nubia_patient/presentation/features/coverage/widgets/coverage_card_picker_button.dart';
import 'package:nubia_patient/core/utils/file_picker_service.dart';

class MockCoverageBloc extends MockBloc<CoverageEvent, CoverageState>
    implements CoverageBloc {}

/// Stub file picker that returns a card image immediately without native channels.
class _StubCardPicker extends FilePickerService {
  const _StubCardPicker();

  @override
  Future<PickedFile?> pickFile() async => const PickedFile(
        path: '/tmp/card.jpg',
        name: 'card.jpg',
        mimeType: 'image/jpeg',
      );
}

const _coverage = HealthCoverage(
  regime: HealthInsuranceRegime.regimeGeneral,
  insuranceName: 'MGEN',
  memberNumber: '123456789',
  thirdPartyPayment: true,
  nssPartial: '2 91 03 …78',
);

/// Wraps the coverage body content directly (bypasses getIt) by providing
/// the bloc via [BlocProvider.value].
Widget _wrap(CoverageBloc bloc, {Widget? body}) {
  return MaterialApp(
    home: BlocProvider<CoverageBloc>.value(
      value: bloc,
      child: body ??
          Scaffold(
            body: BlocBuilder<CoverageBloc, CoverageState>(
              builder: (context, state) {
                if (state is CoverageInitial || state is CoverageLoading) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (state is CoverageError) {
                  return Center(child: Text(state.message));
                }

                HealthCoverage? coverage;
                bool isUploading = false;
                if (state is CoverageLoaded) coverage = state.coverage;
                if (state is CoverageCardUploading) {
                  coverage = state.coverage;
                  isUploading = true;
                }
                if (state is CoverageCardUploaded) coverage = state.coverage;
                if (state is CoverageCardUploadError) coverage = state.coverage;
                if (coverage == null) return const SizedBox.shrink();

                return _CoverageBodyUnwrapped(
                  coverage: coverage,
                  isUploading: isUploading,
                );
              },
            ),
          ),
    ),
  );
}

/// Inline reproduction of the coverage body for testability.
class _CoverageBodyUnwrapped extends StatefulWidget {
  const _CoverageBodyUnwrapped({
    required this.coverage,
    required this.isUploading,
  });

  final HealthCoverage coverage;
  final bool isUploading;

  @override
  State<_CoverageBodyUnwrapped> createState() => _CoverageBodyUnwrappedState();
}

class _CoverageBodyUnwrappedState extends State<_CoverageBodyUnwrapped> {
  String? _filePath;
  String? _filename;
  String? _mimeType;
  CoverageCardSide _side = CoverageCardSide.recto;

  void _onFileSelected({
    required String path,
    required String name,
    required String mime,
    required CoverageCardSide side,
  }) {
    setState(() {
      _filePath = path;
      _filename = name;
      _mimeType = mime;
      _side = side;
    });
  }

  void _submit() {
    final path = _filePath;
    final mime = _mimeType;
    if (path == null || mime == null) return;
    context.read<CoverageBloc>().add(
          CoverageCardUploadRequested(
            filePath: path,
            mimeType: mime,
            side: _side,
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Régime : ${_regimeLabel(widget.coverage.regime)}'),
        if (widget.coverage.nssPartial != null)
          Text('NSS : ${widget.coverage.nssPartial}'),
        if (widget.coverage.insuranceName != null)
          Text(widget.coverage.insuranceName!),
        if (widget.coverage.memberNumber != null)
          Text(widget.coverage.memberNumber!),
        SwitchListTile(
          key: const Key('third_party_payment_toggle'),
          title: const Text('Tiers payant'),
          value: widget.coverage.thirdPartyPayment,
          onChanged: (value) {
            context.read<CoverageBloc>().add(
                  CoverageThirdPartyPaymentToggled(
                    regime: widget.coverage.regime,
                    amc: widget.coverage.insuranceName,
                    numeroAdherent: widget.coverage.memberNumber,
                    thirdPartyPayment: value,
                  ),
                );
          },
        ),
        CoverageCardPickerButton(
          side: CoverageCardSide.recto,
          filename: _filename,
          onFileSelected: _onFileSelected,
          pickerService: const _StubCardPicker(),
        ),
        FilledButton(
          key: const Key('card_upload_submit'),
          onPressed: _filePath != null && !widget.isUploading ? _submit : null,
          child: const Text('Envoyer la carte'),
        ),
      ],
    );
  }

  static String _regimeLabel(HealthInsuranceRegime regime) {
    switch (regime) {
      case HealthInsuranceRegime.regimeGeneral:
        return 'Régime général';
      case HealthInsuranceRegime.ame:
        return 'AME';
      case HealthInsuranceRegime.css:
        return 'CSS';
    }
  }
}

void main() {
  late MockCoverageBloc bloc;

  setUpAll(() {
    registerFallbackValue(const CoverageLoadRequested());
    registerFallbackValue(
      const CoverageCardUploadRequested(
        filePath: '',
        mimeType: '',
        side: CoverageCardSide.recto,
      ),
    );
    registerFallbackValue(
      const CoverageThirdPartyPaymentToggled(
        regime: HealthInsuranceRegime.regimeGeneral,
        thirdPartyPayment: false,
      ),
    );
  });

  setUp(() => bloc = MockCoverageBloc());
  tearDown(() => bloc.close());

  testWidgets('affiche un indicateur de chargement en état Loading',
      (tester) async {
    when(() => bloc.state).thenReturn(const CoverageLoading());

    await tester.pumpWidget(_wrap(bloc));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('affiche la couverture santé en état Loaded', (tester) async {
    when(() => bloc.state).thenReturn(const CoverageLoaded(_coverage));

    await tester.pumpWidget(_wrap(bloc));

    expect(find.text('Régime : Régime général'), findsOneWidget);
    expect(find.text('MGEN'), findsOneWidget);
    expect(find.text('123456789'), findsOneWidget);
    expect(find.text('NSS : 2 91 03 …78'), findsOneWidget);
    expect(
      tester
          .widget<SwitchListTile>(
            find.byKey(const Key('third_party_payment_toggle')),
          )
          .value,
      isTrue,
    );
  });

  testWidgets('affiche un message d\'erreur en état Error', (tester) async {
    when(() => bloc.state).thenReturn(const CoverageError('Erreur réseau.'));

    await tester.pumpWidget(_wrap(bloc));

    expect(find.text('Erreur réseau.'), findsOneWidget);
  });

  testWidgets('le bouton Envoyer est désactivé sans fichier sélectionné',
      (tester) async {
    when(() => bloc.state).thenReturn(const CoverageLoaded(_coverage));

    await tester.pumpWidget(_wrap(bloc));

    final button = tester.widget<FilledButton>(
      find.byKey(const Key('card_upload_submit')),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets(
      'tap le picker et Envoyer déclenche CoverageCardUploadRequested',
      (tester) async {
    when(() => bloc.state).thenReturn(const CoverageLoaded(_coverage));

    await tester.pumpWidget(_wrap(bloc));

    // Tap the card picker button (stub returns card.jpg immediately).
    await tester.tap(find.byKey(const Key('card_picker_recto')));
    await tester.pump();

    // Button is now enabled.
    final button = tester.widget<FilledButton>(
      find.byKey(const Key('card_upload_submit')),
    );
    expect(button.onPressed, isNotNull);

    // Tap submit.
    await tester.tap(find.byKey(const Key('card_upload_submit')));
    await tester.pump();

    verify(
      () => bloc.add(
        const CoverageCardUploadRequested(
          filePath: '/tmp/card.jpg',
          mimeType: 'image/jpeg',
          side: CoverageCardSide.recto,
        ),
      ),
    ).called(1);
  });
}

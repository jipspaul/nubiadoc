import 'dart:typed_data';

import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_secretariat/features/onboarding/onboarding_page.dart';
import 'package:app_secretariat/features/onboarding/provider_stamp_cubit.dart';
import 'package:app_secretariat/session/pro_auth_cubit.dart';

class _MockProAuthCubit extends MockCubit<AuthState> implements ProAuthCubit {}

class _MockProviderStampCubit extends MockCubit<ProviderStampState>
    implements ProviderStampCubit {}

class _MockProviderStampRepository extends Mock
    implements ProviderStampRepository {}

/// PNG 1x1 valide (le back n'accepte que le JPEG, mais `Image.memory` en
/// test décode selon les octets réels, pas le `mimeType` déclaré) — évite
/// l'échec de décodage d'`ImageResourceService` avec des octets arbitraires.
final _kValidPreviewImage = Uint8List.fromList([
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x06,
  0x00,
  0x00,
  0x00,
  0x1F,
  0x15,
  0xC4,
  0x89,
  0x00,
  0x00,
  0x00,
  0x0A,
  0x49,
  0x44,
  0x41,
  0x54,
  0x78,
  0x9C,
  0x63,
  0x00,
  0x01,
  0x00,
  0x00,
  0x05,
  0x00,
  0x01,
  0x0D,
  0x0A,
  0x2D,
  0xB4,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4E,
  0x44,
  0xAE,
  0x42,
  0x60,
  0x82,
]);

Widget _wrap(Widget child, ProAuthCubit cubit) => MaterialApp(
      theme: NubiaTheme.light,
      home: BlocProvider<ProAuthCubit>.value(
        value: cubit,
        child: child,
      ),
    );

void main() {
  group('OnboardingPage — token absent', () {
    testWidgets('affiche message "Invitation invalide" et bouton retour',
        (tester) async {
      final cubit = _MockProAuthCubit();
      when(() => cubit.state).thenReturn(const AuthUnauthenticated());

      await tester.pumpWidget(
        _wrap(const OnboardingPage(invitationToken: null), cubit),
      );

      expect(find.byKey(const Key('onboarding_invalid_token')), findsOneWidget);
      expect(find.text('Invitation invalide'), findsOneWidget);
      expect(find.byKey(const Key('onboarding_back_button')), findsOneWidget);
    });

    testWidgets('affiche message pour token vide', (tester) async {
      final cubit = _MockProAuthCubit();
      when(() => cubit.state).thenReturn(const AuthUnauthenticated());

      await tester.pumpWidget(
        _wrap(const OnboardingPage(invitationToken: ''), cubit),
      );

      expect(find.text('Invitation invalide'), findsOneWidget);
    });
  });

  group('OnboardingPage — token présent', () {
    late _MockProAuthCubit cubit;

    setUp(() {
      cubit = _MockProAuthCubit();
      when(() => cubit.state).thenReturn(const AuthUnauthenticated());
    });

    testWidgets('affiche le formulaire', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const OnboardingPage(invitationToken: 'tok-abc'),
          cubit,
        ),
      );

      expect(find.byKey(const Key('onboarding_email_field')), findsOneWidget);
      expect(
          find.byKey(const Key('onboarding_password_field')), findsOneWidget);
      expect(find.byKey(const Key('onboarding_cgu_checkbox')), findsOneWidget);
      expect(find.byKey(const Key('onboarding_submit_button')), findsOneWidget);
    });

    testWidgets('bouton désactivé si formulaire vide', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const OnboardingPage(invitationToken: 'tok-abc'),
          cubit,
        ),
      );

      final btn = tester.widget<NubiaButton>(
        find.byKey(const Key('onboarding_submit_button')),
      );
      expect(btn.onPressed, isNull);
    });

    testWidgets('bouton activé après saisie email, password et CGU cochée',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          const OnboardingPage(invitationToken: 'tok-abc'),
          cubit,
        ),
      );

      await tester.enterText(
        find.byKey(const Key('onboarding_email_field')),
        'sec@cabinet.fr',
      );
      await tester.enterText(
        find.byKey(const Key('onboarding_password_field')),
        'P@ssw0rd!',
      );
      await tester.tap(find.byKey(const Key('onboarding_cgu_checkbox')));
      await tester.pump();

      final btn = tester.widget<NubiaButton>(
        find.byKey(const Key('onboarding_submit_button')),
      );
      expect(btn.onPressed, isNotNull);
    });
  });

  group('ProviderStampCubit', () {
    late _MockProviderStampRepository repo;
    late ProviderStampCubit cubit;

    final signature = PickedFile(
      path: null,
      name: 'signature.jpg',
      mimeType: 'image/jpeg',
      bytes: Uint8List.fromList([1, 2, 3]),
    );

    setUp(() {
      repo = _MockProviderStampRepository();
      cubit = ProviderStampCubit(
        uploadSignature: UploadProviderSignatureUseCase(repo),
        uploadStamp: UploadProviderStampUseCase(repo),
      );
    });

    blocTest<ProviderStampCubit, ProviderStampState>(
      'upload de la signature : uploading puis signatureUploaded',
      build: () {
        when(() => repo.uploadSignature(
              bytes: any(named: 'bytes'),
              filename: any(named: 'filename'),
              mimeType: any(named: 'mimeType'),
            )).thenAnswer((_) async => const Right('doc-1'));
        return cubit;
      },
      act: (c) => c.pickAndUploadSignature(signature),
      expect: () => [
        ProviderStampState(signature: signature, uploadingSignature: true),
        ProviderStampState(signature: signature, signatureUploaded: true),
      ],
    );

    blocTest<ProviderStampCubit, ProviderStampState>(
      'upload refusé (403, compte non-praticien) : error sans bloquer l\'étape',
      build: () {
        when(() => repo.uploadSignature(
              bytes: any(named: 'bytes'),
              filename: any(named: 'filename'),
              mimeType: any(named: 'mimeType'),
            )).thenAnswer(
          (_) async => const Left(ServerFailure(
            message: 'Accès réservé aux administrateurs du cabinet.',
            statusCode: 403,
          )),
        );
        return cubit;
      },
      act: (c) => c.pickAndUploadSignature(signature),
      expect: () => [
        ProviderStampState(signature: signature, uploadingSignature: true),
        ProviderStampState(
          signature: signature,
          error: 'Accès réservé aux administrateurs du cabinet.',
        ),
      ],
    );
  });

  group('OnboardingPage — compte créé (étape signature/tampon, #7147)', () {
    late _MockProAuthCubit authCubit;
    late _MockProviderStampCubit stampCubit;

    setUp(() {
      authCubit = _MockProAuthCubit();
      when(() => authCubit.state).thenReturn(
        const AuthAuthenticated(
          AuthSession(kind: UserKind.pro, userId: 'u1'),
        ),
      );
      stampCubit = _MockProviderStampCubit();
      when(() => stampCubit.state).thenReturn(const ProviderStampState());
      GetIt.instance.registerFactory<ProviderStampCubit>(() => stampCubit);
      addTearDown(GetIt.instance.reset);
    });

    testWidgets(
        'affiche l\'étape signature/tampon plutôt que de naviguer immédiatement',
        (tester) async {
      await tester.pumpWidget(
        _wrap(const OnboardingPage(invitationToken: 'tok-abc'), authCubit),
      );

      expect(
        find.byKey(const Key('onboarding_profile_setup_scaffold')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('onboarding_pick_signature_button')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('onboarding_pick_stamp_button')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('onboarding_finish_button')), findsOneWidget);
    });

    testWidgets(
        'affiche l\'aperçu et « Envoyée » une fois la signature envoyée',
        (tester) async {
      when(() => stampCubit.state).thenReturn(
        ProviderStampState(
          signature: PickedFile(
            path: null,
            name: 'signature.jpg',
            mimeType: 'image/jpeg',
            bytes: _kValidPreviewImage,
          ),
          signatureUploaded: true,
        ),
      );

      await tester.pumpWidget(
        _wrap(const OnboardingPage(invitationToken: 'tok-abc'), authCubit),
      );

      expect(find.text('Envoyée'), findsOneWidget);
    });

    testWidgets('affiche le message d\'erreur (ex : 403 compte non-praticien)',
        (tester) async {
      when(() => stampCubit.state).thenReturn(
        const ProviderStampState(
          error: 'Accès réservé aux administrateurs du cabinet.',
        ),
      );

      await tester.pumpWidget(
        _wrap(const OnboardingPage(invitationToken: 'tok-abc'), authCubit),
      );

      expect(
        find.text('Accès réservé aux administrateurs du cabinet.'),
        findsOneWidget,
      );
      // Étape sautable malgré l'erreur : le bouton reste disponible.
      expect(find.byKey(const Key('onboarding_finish_button')), findsOneWidget);
    });
  });
}

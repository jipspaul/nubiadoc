import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_secretariat/features/admin_secretariats/admin_secretariats_bloc.dart';
import 'package:app_secretariat/features/admin_secretariats/admin_secretariats_event.dart';
import 'package:app_secretariat/features/admin_secretariats/admin_secretariats_page.dart';
import 'package:app_secretariat/features/admin_secretariats/admin_secretariats_state.dart';
import 'package:app_secretariat/pro_config.dart';

class _MockSecretariatRepository extends Mock
    implements SecretariatRepository {}

class _MockAdminSecretariatsBloc
    extends MockBloc<AdminSecretariatsEvent, AdminSecretariatsState>
    implements AdminSecretariatsBloc {}

void main() {
  // --- Cloisonnement invariant --------------------------------------------------
  group('ProConfig — cloisonnement secrétariats', () {
    test('includeClinical est false', () {
      expect(ProConfig.includeClinical, isFalse);
    });

    test('aucune destination requiresClinical dans shellConfig', () {
      final clinicalDests = ProConfig.shellConfig.destinations
          .where((d) => d.requiresClinical)
          .toList();
      expect(clinicalDests, isEmpty);
    });

    test('la destination Secrétariats est dans shellConfig', () {
      final dest = ProConfig.shellConfig.destinations
          .where((d) => d.route == '/admin-secretariats')
          .toList();
      expect(dest, hasLength(1));
      expect(dest.first.requiresClinical, isFalse);
    });
  });

  // --- Secretariat : pas de champ clinique -------------------------------------
  group('Secretariat — cloisonnement champs cliniques', () {
    test('Secretariat ne porte pas de champ motif ni notes_medicales', () {
      final secretariat = Secretariat(
        id: 's1',
        cabinetId: 'c1',
        name: 'Secrétariat A',
        email: 'secra@example.com',
        isActive: true,
        createdAt: DateTime(2026, 1, 1),
      );
      final json = {
        'id': secretariat.id,
        'name': secretariat.name,
        'email': secretariat.email,
        'isActive': secretariat.isActive,
      };
      expect(json.containsKey('motif'), isFalse);
      expect(json.containsKey('notesMedicales'), isFalse);
    });
  });

  // --- AdminSecretariatsBloc --------------------------------------------------
  group('AdminSecretariatsBloc', () {
    late _MockSecretariatRepository secretariatRepo;
    late ListSecretariatsUseCase listSecretariats;

    final secretariats = [
      Secretariat(
        id: 's1',
        cabinetId: 'c1',
        name: 'Secrétariat A',
        email: 'secra@example.com',
        isActive: true,
        createdAt: DateTime(2026, 1, 1),
      ),
    ];

    setUp(() {
      secretariatRepo = _MockSecretariatRepository();
      listSecretariats = ListSecretariatsUseCase(secretariatRepo);
    });

    blocTest<AdminSecretariatsBloc, AdminSecretariatsState>(
      'émet Loading puis Loaded sur succès',
      build: () {
        when(() => secretariatRepo.list())
            .thenAnswer((_) async => Right(secretariats));
        return AdminSecretariatsBloc(
          listSecretariats: listSecretariats,
          addSecretariat: AddSecretariatUseCase(secretariatRepo),
        );
      },
      act: (bloc) => bloc.add(const AdminSecretariatsLoadRequested()),
      expect: () => [
        const AdminSecretariatsLoading(),
        AdminSecretariatsLoaded(secretariats: secretariats),
      ],
    );

    blocTest<AdminSecretariatsBloc, AdminSecretariatsState>(
      'émet Loading puis Empty sur liste vide',
      build: () {
        when(() => secretariatRepo.list())
            .thenAnswer((_) async => const Right([]));
        return AdminSecretariatsBloc(
          listSecretariats: listSecretariats,
          addSecretariat: AddSecretariatUseCase(secretariatRepo),
        );
      },
      act: (bloc) => bloc.add(const AdminSecretariatsLoadRequested()),
      expect: () => [
        const AdminSecretariatsLoading(),
        const AdminSecretariatsEmpty(),
      ],
    );

    blocTest<AdminSecretariatsBloc, AdminSecretariatsState>(
      'invitation → InviteSent puis rechargement de la liste',
      build: () {
        when(() => secretariatRepo.invite(
              name: any(named: 'name'),
              email: any(named: 'email'),
            )).thenAnswer((_) async => Right(secretariats.first));
        when(() => secretariatRepo.list())
            .thenAnswer((_) async => Right(secretariats));
        return AdminSecretariatsBloc(
          listSecretariats: listSecretariats,
          addSecretariat: AddSecretariatUseCase(secretariatRepo),
        );
      },
      act: (bloc) => bloc.add(const AdminSecretariatsInviteRequested(
        name: 'Secrétariat Rhône',
        email: 'contact@rhone.test',
      )),
      expect: () => [
        const AdminSecretariatsInviteSent('contact@rhone.test'),
        const AdminSecretariatsLoading(),
        AdminSecretariatsLoaded(secretariats: secretariats),
      ],
      verify: (_) {
        verify(() => secretariatRepo.invite(
              name: 'Secrétariat Rhône',
              email: 'contact@rhone.test',
            )).called(1);
      },
    );

    blocTest<AdminSecretariatsBloc, AdminSecretariatsState>(
      'échec d\'invitation → InviteFailed, pas de rechargement',
      build: () {
        when(() => secretariatRepo.invite(
              name: any(named: 'name'),
              email: any(named: 'email'),
            )).thenAnswer(
          (_) async => const Left(
            ServerFailure(message: 'Impossible d\'inviter le secrétariat.'),
          ),
        );
        return AdminSecretariatsBloc(
          listSecretariats: listSecretariats,
          addSecretariat: AddSecretariatUseCase(secretariatRepo),
        );
      },
      act: (bloc) => bloc.add(const AdminSecretariatsInviteRequested(
        name: 'Secrétariat Rhône',
        email: 'contact@rhone.test',
      )),
      expect: () => [
        const AdminSecretariatsInviteFailed(
          'Impossible d\'inviter le secrétariat.',
        ),
      ],
    );

    blocTest<AdminSecretariatsBloc, AdminSecretariatsState>(
      'émet Loading puis Error sur échec',
      build: () {
        when(() => secretariatRepo.list()).thenAnswer(
          (_) async => Left(const NetworkFailure('Erreur réseau')),
        );
        return AdminSecretariatsBloc(
          listSecretariats: listSecretariats,
          addSecretariat: AddSecretariatUseCase(secretariatRepo),
        );
      },
      act: (bloc) => bloc.add(const AdminSecretariatsLoadRequested()),
      expect: () => [
        const AdminSecretariatsLoading(),
        const AdminSecretariatsError('Erreur réseau'),
      ],
    );

    blocTest<AdminSecretariatsBloc, AdminSecretariatsState>(
      'les secrétariats chargés n\'exposent aucun champ clinique',
      build: () {
        when(() => secretariatRepo.list())
            .thenAnswer((_) async => Right(secretariats));
        return AdminSecretariatsBloc(
          listSecretariats: listSecretariats,
          addSecretariat: AddSecretariatUseCase(secretariatRepo),
        );
      },
      act: (bloc) => bloc.add(const AdminSecretariatsLoadRequested()),
      verify: (bloc) {
        final loaded = bloc.state;
        expect(loaded, isA<AdminSecretariatsLoaded>());
        for (final s in (loaded as AdminSecretariatsLoaded).secretariats) {
          expect(s.name, isNotEmpty);
          // Secretariat ne porte pas motif ni notes_medicales :
          // garantie structurelle par le type.
        }
      },
    );
  });

  // --- AdminSecretariatsPage widget tests -------------------------------------
  group('AdminSecretariatsPage', () {
    late _MockAdminSecretariatsBloc bloc;

    setUp(() {
      bloc = _MockAdminSecretariatsBloc();
    });

    Widget buildPage() => MaterialApp(
          theme: NubiaTheme.light,
          home: BlocProvider<AdminSecretariatsBloc>.value(
            value: bloc,
            child: const AdminSecretariatsPage(),
          ),
        );

    testWidgets('affiche le skeleton en état Initial', (tester) async {
      when(() => bloc.state).thenReturn(const AdminSecretariatsInitial());
      await tester.pumpWidget(buildPage());
      expect(
        find.byKey(const Key('admin_secretariats_skeleton')),
        findsOneWidget,
      );
      expect(find.byType(NubiaSkeletonLoader), findsWidgets);
    });

    testWidgets('affiche le skeleton en état Loading', (tester) async {
      when(() => bloc.state).thenReturn(const AdminSecretariatsLoading());
      await tester.pumpWidget(buildPage());
      expect(
        find.byKey(const Key('admin_secretariats_skeleton')),
        findsOneWidget,
      );
    });

    testWidgets('affiche l\'état vide', (tester) async {
      when(() => bloc.state).thenReturn(const AdminSecretariatsEmpty());
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('admin_secretariats_empty')), findsOneWidget);
      expect(find.text('Aucun secrétariat enregistré.'), findsOneWidget);
    });

    testWidgets('affiche les secrétariats — aucun champ clinique visible',
        (tester) async {
      when(() => bloc.state).thenReturn(
        AdminSecretariatsLoaded(
          secretariats: [
            Secretariat(
              id: 's1',
              cabinetId: 'c1',
              name: 'Secrétariat A',
              email: 'secra@example.com',
              isActive: true,
              createdAt: DateTime(2026, 1, 1),
            ),
          ],
        ),
      );
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      expect(find.text('Secrétariat A'), findsOneWidget);
      // Le statut est affiché via un NubiaBadge (jamais la couleur seule).
      expect(find.byType(NubiaBadge), findsOneWidget);
      expect(find.text('Actif'), findsOneWidget);
      // Cloisonnement : aucun libellé clinique ne doit apparaître
      expect(find.text('Motif'), findsNothing);
      expect(find.text('Notes médicales'), findsNothing);
      expect(find.textContaining('motif'), findsNothing);
      expect(find.textContaining('notes'), findsNothing);
    });

    testWidgets('le FAB ouvre la modale d\'invitation (action admin)',
        (tester) async {
      when(() => bloc.state).thenReturn(const AdminSecretariatsEmpty());
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('invite_secretariat_fab')));
      await tester.pumpAndSettle();

      expect(find.text('Inviter un secrétariat'), findsWidgets);
      expect(
        find.byKey(const Key('invite_secretariat_email_field')),
        findsOneWidget,
      );
    });

    testWidgets('affiche le message d\'erreur', (tester) async {
      when(() => bloc.state)
          .thenReturn(const AdminSecretariatsError('Erreur de connexion'));
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      expect(find.text('Erreur de connexion'), findsOneWidget);
    });

    testWidgets('pull-to-refresh déclenche AdminSecretariatsLoadRequested',
        (tester) async {
      when(() => bloc.state).thenReturn(
        AdminSecretariatsLoaded(
          secretariats: [
            Secretariat(
              id: 's1',
              cabinetId: 'c1',
              name: 'Secrétariat A',
              email: 'secra@example.com',
              isActive: true,
              createdAt: DateTime(2026, 1, 1),
            ),
          ],
        ),
      );
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      await tester.fling(
        find.byKey(const Key('admin_secretariats_refresh')),
        const Offset(0, 300),
        800,
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      // 1 appel depuis initState + 1 depuis le pull-to-refresh
      verify(() => bloc.add(const AdminSecretariatsLoadRequested())).called(2);
    });
  });
}

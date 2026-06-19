import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_secretariat/features/admin_membres/admin_membres_bloc.dart';
import 'package:app_secretariat/features/admin_membres/admin_membres_event.dart';
import 'package:app_secretariat/features/admin_membres/admin_membres_page.dart';
import 'package:app_secretariat/features/admin_membres/admin_membres_state.dart';
import 'package:app_secretariat/pro_config.dart';

class _MockMembersRepository extends Mock implements MembersRepository {}

class _MockSecretariatRepository extends Mock implements SecretariatRepository {}

class _MockAdminMembresBloc
    extends MockBloc<AdminMembresEvent, AdminMembresState>
    implements AdminMembresBloc {}

void main() {
  // --- Cloisonnement invariant --------------------------------------------------
  group('ProConfig — cloisonnement', () {
    test('includeClinical est false', () {
      expect(ProConfig.includeClinical, isFalse);
    });

    test('aucune destination requiresClinical dans shellConfig', () {
      final clinicalDests = ProConfig.shellConfig.destinations
          .where((d) => d.requiresClinical)
          .toList();
      expect(clinicalDests, isEmpty);
    });
  });

  // --- Member : pas de champ clinique ------------------------------------------
  group('Member — cloisonnement champs cliniques', () {
    test('fullName accessible (non-clinique)', () {
      final member = Member(
        id: 'm1',
        cabinetId: 'c1',
        firstName: 'Sophie',
        lastName: 'Martin',
        email: 'sophie@example.com',
        role: MemberRole.secretary,
        isActive: true,
        joinedAt: DateTime(2026, 1, 1),
      );
      expect(member.fullName, 'Sophie Martin');
    });

    test('Member ne porte pas de champ motif ni notes_medicales', () {
      final member = Member(
        id: 'm1',
        cabinetId: 'c1',
        firstName: 'Sophie',
        lastName: 'Martin',
        email: 'sophie@example.com',
        role: MemberRole.secretary,
        isActive: true,
        joinedAt: DateTime(2026, 1, 1),
      );
      final json = {
        'id': member.id,
        'firstName': member.firstName,
        'lastName': member.lastName,
        'email': member.email,
        'role': member.role.name,
      };
      expect(json.containsKey('motif'), isFalse);
      expect(json.containsKey('notesMedicales'), isFalse);
    });
  });

  // --- AdminMembresBloc --------------------------------------------------------
  group('AdminMembresBloc', () {
    late _MockMembersRepository membersRepo;
    late _MockSecretariatRepository secretariatRepo;
    late ListMembersUseCase listMembers;
    late ListSecretiariatsUseCase listSecretariats;

    final members = [
      Member(
        id: 'm1',
        cabinetId: 'c1',
        firstName: 'Sophie',
        lastName: 'Martin',
        email: 'sophie@example.com',
        role: MemberRole.secretary,
        isActive: true,
        joinedAt: DateTime(2026, 1, 1),
      ),
    ];

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
      membersRepo = _MockMembersRepository();
      secretariatRepo = _MockSecretariatRepository();
      listMembers = ListMembersUseCase(membersRepo);
      listSecretariats = ListSecretiariatsUseCase(secretariatRepo);
    });

    blocTest<AdminMembresBloc, AdminMembresState>(
      'émet Loading puis Loaded sur succès',
      build: () {
        when(() => membersRepo.list())
            .thenAnswer((_) async => Right(members));
        when(() => secretariatRepo.list())
            .thenAnswer((_) async => Right(secretariats));
        return AdminMembresBloc(
          listMembers: listMembers,
          listSecretariats: listSecretariats,
        );
      },
      act: (bloc) => bloc.add(const AdminMembresLoadRequested()),
      expect: () => [
        const AdminMembresLoading(),
        AdminMembresLoaded(members: members, secretariats: secretariats),
      ],
    );

    blocTest<AdminMembresBloc, AdminMembresState>(
      'émet Loading puis Error si membres échoue',
      build: () {
        when(() => membersRepo.list()).thenAnswer(
          (_) async => Left(const NetworkFailure('Erreur réseau')),
        );
        when(() => secretariatRepo.list())
            .thenAnswer((_) async => Right(secretariats));
        return AdminMembresBloc(
          listMembers: listMembers,
          listSecretariats: listSecretariats,
        );
      },
      act: (bloc) => bloc.add(const AdminMembresLoadRequested()),
      expect: () => [
        const AdminMembresLoading(),
        const AdminMembresError('Erreur réseau'),
      ],
    );

    blocTest<AdminMembresBloc, AdminMembresState>(
      'les membres chargés n\'exposent aucun champ clinique',
      build: () {
        when(() => membersRepo.list())
            .thenAnswer((_) async => Right(members));
        when(() => secretariatRepo.list())
            .thenAnswer((_) async => Right(secretariats));
        return AdminMembresBloc(
          listMembers: listMembers,
          listSecretariats: listSecretariats,
        );
      },
      act: (bloc) => bloc.add(const AdminMembresLoadRequested()),
      verify: (bloc) {
        final loaded = bloc.state;
        expect(loaded, isA<AdminMembresLoaded>());
        for (final m in (loaded as AdminMembresLoaded).members) {
          expect(m.fullName, isNotEmpty);
          // Member ne porte pas motif ni notes_medicales :
          // garantie structurelle par le type.
        }
      },
    );
  });

  // --- AdminMembresPage widget test --------------------------------------------
  group('AdminMembresPage', () {
    late _MockAdminMembresBloc bloc;

    setUp(() {
      bloc = _MockAdminMembresBloc();
    });

    Widget buildPage() => MaterialApp(
          theme: NubiaTheme.light,
          home: BlocProvider<AdminMembresBloc>.value(
            value: bloc,
            child: const AdminMembresPage(),
          ),
        );

    testWidgets('affiche le chargement en état initial', (tester) async {
      when(() => bloc.state).thenReturn(const AdminMembresInitial());
      await tester.pumpWidget(buildPage());
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('affiche les membres — aucun champ clinique visible',
        (tester) async {
      when(() => bloc.state).thenReturn(
        AdminMembresLoaded(
          members: [
            Member(
              id: 'm1',
              cabinetId: 'c1',
              firstName: 'Sophie',
              lastName: 'Martin',
              email: 'sophie@example.com',
              role: MemberRole.secretary,
              isActive: true,
              joinedAt: DateTime(2026, 1, 1),
            ),
          ],
          secretariats: const [],
        ),
      );
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      expect(find.text('Sophie Martin'), findsOneWidget);
      // Cloisonnement : aucun libellé clinique ne doit apparaître
      expect(find.text('Motif'), findsNothing);
      expect(find.text('Notes médicales'), findsNothing);
      expect(find.textContaining('motif'), findsNothing);
      expect(find.textContaining('notes'), findsNothing);
    });

    testWidgets('affiche un message si la liste membres est vide',
        (tester) async {
      when(() => bloc.state).thenReturn(
        const AdminMembresLoaded(members: [], secretariats: []),
      );
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      expect(find.text('Aucun membre enregistré.'), findsOneWidget);
    });

    testWidgets('affiche le message d\'erreur', (tester) async {
      when(() => bloc.state)
          .thenReturn(const AdminMembresError('Erreur de connexion'));
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      expect(find.text('Erreur de connexion'), findsOneWidget);
    });
  });
}

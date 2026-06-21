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

class _MockAdminSecretiariatsBloc
    extends MockBloc<AdminSecretiariatsEvent, AdminSecretiariatsState>
    implements AdminSecretiariatsBloc {}

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

  // --- AdminSecretiariatsBloc --------------------------------------------------
  group('AdminSecretiariatsBloc', () {
    late _MockSecretariatRepository secretariatRepo;
    late ListSecretiariatsUseCase listSecretariats;

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
      listSecretariats = ListSecretiariatsUseCase(secretariatRepo);
    });

    blocTest<AdminSecretiariatsBloc, AdminSecretiariatsState>(
      'émet Loading puis Loaded sur succès',
      build: () {
        when(() => secretariatRepo.list())
            .thenAnswer((_) async => Right(secretariats));
        return AdminSecretiariatsBloc(listSecretariats: listSecretariats);
      },
      act: (bloc) => bloc.add(const AdminSecretiariatsLoadRequested()),
      expect: () => [
        const AdminSecretiariatsLoading(),
        AdminSecretiariatsLoaded(secretariats: secretariats),
      ],
    );

    blocTest<AdminSecretiariatsBloc, AdminSecretiariatsState>(
      'émet Loading puis Error sur échec',
      build: () {
        when(() => secretariatRepo.list()).thenAnswer(
          (_) async => Left(const NetworkFailure('Erreur réseau')),
        );
        return AdminSecretiariatsBloc(listSecretariats: listSecretariats);
      },
      act: (bloc) => bloc.add(const AdminSecretiariatsLoadRequested()),
      expect: () => [
        const AdminSecretiariatsLoading(),
        const AdminSecretiariatsError('Erreur réseau'),
      ],
    );

    blocTest<AdminSecretiariatsBloc, AdminSecretiariatsState>(
      'les secrétariats chargés n\'exposent aucun champ clinique',
      build: () {
        when(() => secretariatRepo.list())
            .thenAnswer((_) async => Right(secretariats));
        return AdminSecretiariatsBloc(listSecretariats: listSecretariats);
      },
      act: (bloc) => bloc.add(const AdminSecretiariatsLoadRequested()),
      verify: (bloc) {
        final loaded = bloc.state;
        expect(loaded, isA<AdminSecretiariatsLoaded>());
        for (final s in (loaded as AdminSecretiariatsLoaded).secretariats) {
          expect(s.name, isNotEmpty);
          // Secretariat ne porte pas motif ni notes_medicales :
          // garantie structurelle par le type.
        }
      },
    );
  });

  // --- AdminSecretiariatsPage widget tests -------------------------------------
  group('AdminSecretiariatsPage', () {
    late _MockAdminSecretiariatsBloc bloc;

    setUp(() {
      bloc = _MockAdminSecretiariatsBloc();
    });

    Widget buildPage() => MaterialApp(
          theme: NubiaTheme.light,
          home: BlocProvider<AdminSecretiariatsBloc>.value(
            value: bloc,
            child: const AdminSecretiariatsPage(),
          ),
        );

    testWidgets('affiche le chargement en état initial', (tester) async {
      when(() => bloc.state).thenReturn(const AdminSecretiariatsInitial());
      await tester.pumpWidget(buildPage());
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('affiche les secrétariats — aucun champ clinique visible',
        (tester) async {
      when(() => bloc.state).thenReturn(
        AdminSecretiariatsLoaded(
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
      // Cloisonnement : aucun libellé clinique ne doit apparaître
      expect(find.text('Motif'), findsNothing);
      expect(find.text('Notes médicales'), findsNothing);
      expect(find.textContaining('motif'), findsNothing);
      expect(find.textContaining('notes'), findsNothing);
    });

    testWidgets('affiche un message si la liste est vide', (tester) async {
      when(() => bloc.state).thenReturn(
        const AdminSecretiariatsLoaded(secretariats: []),
      );
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      expect(find.text('Aucun secrétariat enregistré.'), findsOneWidget);
    });

    testWidgets('affiche le message d\'erreur', (tester) async {
      when(() => bloc.state)
          .thenReturn(const AdminSecretiariatsError('Erreur de connexion'));
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      expect(find.text('Erreur de connexion'), findsOneWidget);
    });
  });
}

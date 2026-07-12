import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_secretariat/features/admin_membres/invite_member_dialog.dart';

typedef _InviteResult = ({
  String email,
  MemberRole role,
  String firstName,
  String lastName,
});

Widget _buildTestScaffold({
  ValueChanged<_InviteResult?>? onResult,
}) {
  return MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => ElevatedButton(
          key: const Key('open_dialog'),
          onPressed: () async {
            final result = await showDialog<_InviteResult>(
              context: context,
              builder: (_) => const InviteMemberDialog(),
            );
            onResult?.call(result);
          },
          child: const Text('Ouvrir'),
        ),
      ),
    ),
  );
}

// Remplit les 3 champs requis (prénom, nom, email) du dialogue d'invitation :
// l'API POST /v1/cabinet/members exige first_name + last_name en plus de l'email.
Future<void> _fillRequiredFields(
  WidgetTester tester, {
  String firstName = 'Alice',
  String lastName = 'Martin',
  String email = 'invite@cabinet.fr',
}) async {
  await tester.enterText(
    find.byKey(const Key('invite_first_name_field')),
    firstName,
  );
  await tester.enterText(
    find.byKey(const Key('invite_last_name_field')),
    lastName,
  );
  await tester.enterText(find.byKey(const Key('invite_email_field')), email);
  await tester.pump();
}

void main() {
  testWidgets(
      'ouverture dialog affiche prénom/nom/email, dropdown rôle et bouton Inviter',
      (tester) async {
    await tester.pumpWidget(_buildTestScaffold());

    await tester.tap(find.byKey(const Key('open_dialog')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('invite_first_name_field')), findsOneWidget);
    expect(find.byKey(const Key('invite_last_name_field')), findsOneWidget);
    expect(find.byKey(const Key('invite_email_field')), findsOneWidget);
    expect(find.byKey(const Key('invite_role_dropdown')), findsOneWidget);
    expect(find.byKey(const Key('invite_submit_button')), findsOneWidget);
  });

  testWidgets(
      'bouton Inviter désactivé tant que prénom/nom/email ne sont pas tous remplis',
      (tester) async {
    await tester.pumpWidget(_buildTestScaffold());

    await tester.tap(find.byKey(const Key('open_dialog')));
    await tester.pumpAndSettle();

    ElevatedButton submit() => tester.widget<ElevatedButton>(
          find.byKey(const Key('invite_submit_button')),
        );

    // Rien de rempli -> désactivé.
    expect(submit().onPressed, isNull);

    // Email seul -> toujours désactivé (prénom + nom requis).
    await tester.enterText(
      find.byKey(const Key('invite_email_field')),
      'user@example.com',
    );
    await tester.pump();
    expect(submit().onPressed, isNull);

    // Les 3 champs requis remplis -> activé.
    await _fillRequiredFields(tester, email: 'user@example.com');
    expect(submit().onPressed, isNotNull);
  });

  testWidgets(
      'tap Inviter ferme le dialog et retourne prénom, nom, email et rôle',
      (tester) async {
    _InviteResult? result;
    await tester.pumpWidget(
      _buildTestScaffold(onResult: (r) => result = r),
    );

    await tester.tap(find.byKey(const Key('open_dialog')));
    await tester.pumpAndSettle();

    await _fillRequiredFields(
      tester,
      firstName: 'Alice',
      lastName: 'Martin',
      email: 'invite@cabinet.fr',
    );

    await tester.tap(find.byKey(const Key('invite_submit_button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('invite_email_field')), findsNothing);
    expect(result?.email, 'invite@cabinet.fr');
    expect(result?.firstName, 'Alice');
    expect(result?.lastName, 'Martin');
    expect(result?.role, MemberRole.secretary);
  });
}

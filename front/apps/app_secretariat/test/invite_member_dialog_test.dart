import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_secretariat/features/admin_membres/invite_member_dialog.dart';

Widget _buildTestScaffold({
  ValueChanged<({String email, MemberRole role})?>? onResult,
}) {
  return MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => ElevatedButton(
          key: const Key('open_dialog'),
          onPressed: () async {
            final result =
                await showDialog<({String email, MemberRole role})>(
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

void main() {
  testWidgets(
      'ouverture dialog affiche champ email, dropdown rôle et bouton Inviter',
      (tester) async {
    await tester.pumpWidget(_buildTestScaffold());

    await tester.tap(find.byKey(const Key('open_dialog')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('invite_email_field')), findsOneWidget);
    expect(find.byKey(const Key('invite_role_dropdown')), findsOneWidget);
    expect(find.byKey(const Key('invite_submit_button')), findsOneWidget);
  });

  testWidgets(
      'bouton Inviter désactivé si email invalide, activé si email valide',
      (tester) async {
    await tester.pumpWidget(_buildTestScaffold());

    await tester.tap(find.byKey(const Key('open_dialog')));
    await tester.pumpAndSettle();

    final submitButton = tester.widget<ElevatedButton>(
      find.byKey(const Key('invite_submit_button')),
    );
    expect(submitButton.onPressed, isNull);

    await tester.enterText(
      find.byKey(const Key('invite_email_field')),
      'user@example.com',
    );
    await tester.pump();

    final submitButtonEnabled = tester.widget<ElevatedButton>(
      find.byKey(const Key('invite_submit_button')),
    );
    expect(submitButtonEnabled.onPressed, isNotNull);
  });

  testWidgets(
      'tap Inviter ferme le dialog et retourne l\'email et le rôle saisis',
      (tester) async {
    ({String email, MemberRole role})? result;
    await tester.pumpWidget(
      _buildTestScaffold(onResult: (r) => result = r),
    );

    await tester.tap(find.byKey(const Key('open_dialog')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('invite_email_field')),
      'invite@cabinet.fr',
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('invite_submit_button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('invite_email_field')), findsNothing);
    expect(result?.email, 'invite@cabinet.fr');
    expect(result?.role, MemberRole.secretary);
  });
}

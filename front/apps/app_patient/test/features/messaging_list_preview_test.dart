// Issue #3348 — la liste des conversations doit être lisible : aperçu du
// dernier message (last_message_preview) et horodatage (last_message_at),
// même quand l'API liste ne renvoie pas d'objet lastMessage complet.
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_patient/features/messaging/messaging_bloc.dart';
import 'package:app_patient/features/messaging/messaging_event.dart';
import 'package:app_patient/features/messaging/messaging_page.dart';
import 'package:app_patient/features/messaging/messaging_state.dart';

class MockMessagingBloc extends MockBloc<MessagingEvent, MessagingState>
    implements MessagingBloc {}

Widget _wrap(MessagingBloc bloc) => MaterialApp(
      theme: NubiaTheme.light,
      home: Scaffold(
        body: BlocProvider<MessagingBloc>.value(
          value: bloc,
          child: const MessagingPage(),
        ),
      ),
    );

void main() {
  testWidgets('affiche l\'aperçu et la date du dernier message',
      (tester) async {
    final bloc = MockMessagingBloc();
    when(() => bloc.state).thenReturn(
      MessagingConversationsLoaded([
        Conversation(
          id: 'c1',
          cabinetId: 'cab',
          cabinetName: 'Cabinet Lyon',
          unreadCount: 2,
          lastMessageAt: DateTime(2026, 3, 12, 9, 30),
          lastMessagePreview: 'Vos résultats sont disponibles.',
        ),
      ]),
    );

    await tester.pumpWidget(_wrap(bloc));

    expect(find.text('Cabinet Lyon'), findsOneWidget);
    expect(find.text('Vos résultats sont disponibles.'), findsOneWidget);
    expect(find.text('12 mar'), findsOneWidget);
  });

  // Régression #3856 : lastMessageAt vient de DateTime.parse() sur un ISO
  // avec offset (+00:00) → isUtc == true. Afficher .hour/.minute bruts
  // montrait l'heure UTC au lieu de l'heure locale (-2h été/-1h hiver pour
  // Europe/Paris). Construit un instant UTC équivalent à "maintenant, heure
  // locale" (peu importe le fuseau réel de la machine de test) : si l'heure
  // affichée correspond à l'heure locale attendue plutôt qu'à l'heure UTC
  // brute, la conversion .toLocal() est bien appliquée.
  testWidgets('affiche l\'heure locale, pas l\'heure UTC brute',
      (tester) async {
    final nowLocal = DateTime.now();
    // "Aujourd'hui, il y a 5 minutes" en LOCAL, converti en UTC pour
    // simuler le contrat serveur (ISO + offset → DateTime.parse isUtc=true).
    final localMoment = DateTime(nowLocal.year, nowLocal.month, nowLocal.day,
            nowLocal.hour, nowLocal.minute)
        .subtract(const Duration(minutes: 5));
    final expectedHHmm =
        '${localMoment.hour.toString().padLeft(2, '0')}:${localMoment.minute.toString().padLeft(2, '0')}';
    final utcMoment = localMoment.toUtc();

    final bloc = MockMessagingBloc();
    when(() => bloc.state).thenReturn(
      MessagingConversationsLoaded([
        Conversation(
          id: 'c-tz',
          cabinetId: 'cab',
          cabinetName: 'Cabinet TZ',
          unreadCount: 1,
          lastMessageAt: utcMoment,
          lastMessagePreview: 'Message récent',
        ),
      ]),
    );

    await tester.pumpWidget(_wrap(bloc));

    expect(
      find.text(expectedHHmm),
      findsOneWidget,
      reason:
          'doit afficher $expectedHHmm (heure locale), pas l\'heure UTC brute ${utcMoment.hour}:${utcMoment.minute}',
    );
  });

  testWidgets('reste rendable sans aperçu ni date (anciens payloads)',
      (tester) async {
    final bloc = MockMessagingBloc();
    when(() => bloc.state).thenReturn(
      MessagingConversationsLoaded([
        const Conversation(
          id: 'c1',
          cabinetId: 'cab',
          cabinetName: 'Cabinet Lyon',
          unreadCount: 0,
        ),
      ]),
    );

    await tester.pumpWidget(_wrap(bloc));

    expect(find.text('Cabinet Lyon'), findsOneWidget);
    expect(find.byKey(const Key('conv_c1')), findsOneWidget);
  });
}

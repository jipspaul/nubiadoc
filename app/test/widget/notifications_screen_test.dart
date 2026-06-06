import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_patient/domain/entities/app_notification.dart';
import 'package:nubia_patient/presentation/features/notifications/bloc/notification_bloc.dart';
import 'package:nubia_patient/presentation/features/notifications/bloc/notification_event.dart';
import 'package:nubia_patient/presentation/features/notifications/bloc/notification_state.dart';
import 'package:nubia_patient/presentation/features/notifications/pages/notifications_screen.dart';
import 'package:nubia_patient/presentation/features/notifications/widgets/notification_tile.dart';

class MockNotificationBloc
    extends MockBloc<NotificationEvent, NotificationState>
    implements NotificationBloc {}

final _notifications = [
  AppNotification(
    id: 'n1',
    type: NotificationType.appointment,
    title: 'Rappel RDV',
    body: 'Votre RDV est demain à 9h00.',
    read: false,
    createdAt: DateTime(2026, 6, 6, 8, 0),
  ),
  AppNotification(
    id: 'n2',
    type: NotificationType.message,
    title: 'Nouveau message',
    body: 'Cabinet Dupont vous a écrit.',
    read: true,
    createdAt: DateTime(2026, 6, 5, 14, 30),
  ),
];

Widget _wrap(NotificationBloc bloc) {
  return MaterialApp(
    home: BlocProvider<NotificationBloc>.value(
      value: bloc,
      child: const NotificationsScreen(),
    ),
  );
}

void main() {
  late MockNotificationBloc bloc;

  setUp(() {
    bloc = MockNotificationBloc();
  });

  tearDown(() => bloc.close());

  testWidgets('affiche un indicateur de chargement en état Loading',
      (tester) async {
    when(() => bloc.state).thenReturn(const NotificationLoading());

    await tester.pumpWidget(_wrap(bloc));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('affiche un message d\'erreur en état Error', (tester) async {
    when(() => bloc.state)
        .thenReturn(const NotificationError('Erreur réseau.'));

    await tester.pumpWidget(_wrap(bloc));

    expect(find.text('Erreur réseau.'), findsOneWidget);
  });

  testWidgets('affiche la liste des notifications en état Loaded',
      (tester) async {
    when(() => bloc.state)
        .thenReturn(NotificationLoaded(_notifications));

    await tester.pumpWidget(_wrap(bloc));

    expect(find.byType(NotificationTile), findsNWidgets(2));
    expect(find.text('Rappel RDV'), findsOneWidget);
    expect(find.text('Nouveau message'), findsOneWidget);
  });

  testWidgets('affiche l\'écran vide quand il n\'y a aucune notification',
      (tester) async {
    when(() => bloc.state).thenReturn(const NotificationLoaded([]));

    await tester.pumpWidget(_wrap(bloc));

    expect(find.text('Aucune notification'), findsOneWidget);
  });

  testWidgets('affiche le bouton "Tout lire" quand il y a des non lus',
      (tester) async {
    when(() => bloc.state)
        .thenReturn(NotificationLoaded(_notifications));

    await tester.pumpWidget(_wrap(bloc));

    expect(find.text('Tout lire'), findsOneWidget);
  });
}

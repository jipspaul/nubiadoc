//! Tests : `AuditLogBody`/`AuditLogBloc` (#4155) — affichage de la liste du
//! journal d'accès et de l'état vide/rempli. Golden test indisponible dans ce
//! monorepo (aucune infra golden_toolkit/goldens/ n'existe ailleurs) —
//! substitué par ces tests widget standard, même convention que
//! `cabinet_stats_test.dart`.
//!
//! `MockAuditLogBloc` (état fixé directement) — évite de faire tourner un
//! vrai Bloc dans un test widget. Pas de `bloc.close()` sur un Bloc injecté
//! via `BlocProvider.value` (piège documenté dans `stock_inventory_test.dart`,
//! app_practicien).

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_secretariat/features/audit_log/audit_log_bloc.dart';
import 'package:app_secretariat/features/audit_log/audit_log_event.dart';
import 'package:app_secretariat/features/audit_log/audit_log_page.dart';
import 'package:app_secretariat/features/audit_log/audit_log_state.dart';

class MockAuditLogBloc extends MockBloc<AuditLogEvent, AuditLogState>
    implements AuditLogBloc {}

final _entries = [
  AuditLogEntry(
    id: 2,
    actorId: 'user-1',
    actorRole: 'admin',
    action: 'read_record',
    entity: 'patient',
    entityId: 'patient-1',
    occurredAt: DateTime.utc(2026, 7, 20, 10, 30),
  ),
  AuditLogEntry(
    id: 1,
    actorId: 'user-1',
    actorRole: 'admin',
    action: 'login',
    entity: 'session',
    occurredAt: DateTime.utc(2026, 7, 20, 9, 0),
  ),
];

Widget _wrap(AuditLogBloc bloc) => MaterialApp(
      theme: NubiaTheme.light,
      // Scaffold : la barre de filtres utilise `NubiaTextField` (TextField
      // Material, requiert un ancêtre Material — absent d'un simple `home:`).
      home: Scaffold(
        body: BlocProvider<AuditLogBloc>.value(
          value: bloc,
          child: const AuditLogBody(),
        ),
      ),
    );

void main() {
  testWidgets('affiche la liste des entrées du journal d\'accès',
      (tester) async {
    final bloc = MockAuditLogBloc();
    when(() => bloc.state).thenReturn(AuditLogLoaded(_entries));
    await tester.pumpWidget(_wrap(bloc));

    expect(find.byKey(const Key('audit_log_loaded')), findsOneWidget);
    expect(find.byKey(const Key('audit_log_entry_2')), findsOneWidget);
    expect(find.byKey(const Key('audit_log_entry_1')), findsOneWidget);
    expect(find.text('read_record · patient'), findsOneWidget);
    expect(find.text('login · session'), findsOneWidget);
  });

  testWidgets('aucune entrée sur la période → état vide', (tester) async {
    final bloc = MockAuditLogBloc();
    when(() => bloc.state).thenReturn(const AuditLogLoaded([]));
    await tester.pumpWidget(_wrap(bloc));

    expect(find.byKey(const Key('audit_log_empty')), findsOneWidget);
  });

  testWidgets('403 (rôle non-admin) → état accès refusé', (tester) async {
    final bloc = MockAuditLogBloc();
    when(() => bloc.state)
        .thenReturn(const AuditLogForbidden('Accès réservé.'));
    await tester.pumpWidget(_wrap(bloc));

    expect(find.byKey(const Key('audit_log_forbidden')), findsOneWidget);
  });
}

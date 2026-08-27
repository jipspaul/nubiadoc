// #5050 — l'activité hebdomadaire (actes réalisés, honoraires, RDV non
// honorés) était absente du domaine du dashboard praticien. Déjà exposée
// par #5051 (carte « Cette semaine ») ; ce test verrouille le contrat au
// niveau domaine pour éviter toute régression future.
import 'package:nubia_domain/nubia_domain.dart';
import 'package:test/test.dart';

void main() {
  group('ProDashboardSummary', () {
    test('expose les 3 agrégats hebdomadaires, honoraires en centimes', () {
      const summary = ProDashboardSummary(
        todayAppointments: 3,
        waitingRoomCount: 1,
        unreadMessages: 2,
        pendingConfirmations: 0,
        weeklyCompletedActs: 38,
        weeklyFeesCents: 642000,
        weeklyNoShowCount: 2,
      );

      expect(summary.weeklyCompletedActs, 38);
      expect(summary.weeklyFeesCents, 642000,
          reason: 'les honoraires sont stockés en centimes, pas formatés');
      expect(summary.weeklyNoShowCount, 2);
    });

    test('conserve les 4 compteurs existants (non-régression)', () {
      const summary = ProDashboardSummary(
        todayAppointments: 5,
        waitingRoomCount: 4,
        unreadMessages: 3,
        pendingConfirmations: 2,
        weeklyCompletedActs: 0,
        weeklyFeesCents: 0,
        weeklyNoShowCount: 0,
      );

      expect(summary.todayAppointments, 5);
      expect(summary.waitingRoomCount, 4);
      expect(summary.unreadMessages, 3);
      expect(summary.pendingConfirmations, 2);
    });

    test('le patient suivant (#5045) est absent par défaut', () {
      const summary = ProDashboardSummary(
        todayAppointments: 0,
        waitingRoomCount: 0,
        unreadMessages: 0,
        pendingConfirmations: 0,
        weeklyCompletedActs: 0,
        weeklyFeesCents: 0,
        weeklyNoShowCount: 0,
      );

      expect(summary.nextPatientName, isNull);
      expect(summary.nextPatientReason, isNull);
      expect(summary.nextPatientAppointmentTime, isNull);
      expect(summary.nextPatientDurationMinutes, isNull);
      expect(summary.nextPatientWaitingMinutes, isNull);
      expect(summary.nextPatientAllergyLabel, isNull);
      expect(summary.nextPatientTreatmentPlanCents, isNull);
      expect(summary.nextPatientLastVisitAt, isNull);
    });

    test('expose le patient suivant quand présent', () {
      final summary = ProDashboardSummary(
        todayAppointments: 9,
        waitingRoomCount: 1,
        unreadMessages: 0,
        pendingConfirmations: 0,
        weeklyCompletedActs: 0,
        weeklyFeesCents: 0,
        weeklyNoShowCount: 0,
        nextPatientName: 'Camille Moreau',
        nextPatientReason: 'Pose de couronne',
        nextPatientAppointmentTime: DateTime(2026, 8, 26, 14, 30),
        nextPatientDurationMinutes: 30,
        nextPatientWaitingMinutes: 12,
      );

      expect(summary.nextPatientName, 'Camille Moreau');
      expect(summary.nextPatientReason, 'Pose de couronne');
      expect(summary.nextPatientDurationMinutes, 30);
      expect(summary.nextPatientWaitingMinutes, 12);
    });
  });
}

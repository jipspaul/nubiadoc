import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_data/nubia_data.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_pharmacie/pharma_config.dart';
import 'package:app_pharmacie/session/pharma_di.dart';

/// Invariants de cloisonnement de l'app pharmacie (défense en profondeur,
/// pattern app_secretariat) : le DI réel de l'app ne contient AUCUN chemin
/// vers les données cliniques ni vers l'espace patient.
void main() {
  final gi = GetIt.instance;

  setUp(() async {
    await gi.reset();
    registerCore(gi);
    // Même câblage que bootstrap.dart — codé en dur, ne jamais passer true.
    registerData(
      gi,
      includeClinical: false,
      includePro: false,
      includePharmacy: true,
    );
    registerPharma(gi);
  });

  tearDown(() async => gi.reset());

  test('aucun repo clinique enregistré (prescription, consultation)', () {
    expect(gi.isRegistered<PrescriptionRepository>(), isFalse);
    expect(gi.isRegistered<ConsultationRepository>(), isFalse);
    expect(gi.isRegistered<ClinicalSessionRepository>(), isFalse);
  });

  test('aucun repo patient enregistré (espace /v1/account)', () {
    expect(gi.isRegistered<PatientPharmacyRepository>(), isFalse);
  });

  test('le stack pharmacie est complet', () {
    expect(gi.isRegistered<PharmacyOrdersRepository>(), isTrue);
    expect(gi.isRegistered<StockRequestsRepository>(), isTrue);
    expect(gi.isRegistered<PharmacyQuotesRepository>(), isTrue);
    expect(gi.isRegistered<CabinetMessageRepository>(), isTrue);
    expect(gi.isRegistered<PharmacyOrderEventsPort>(), isTrue);
  });

  test('les 4 destinations de nav sont déclarées, aucune clinique', () {
    final destinations = PharmaConfig.shellConfig.destinations;
    expect(destinations, hasLength(4));
    expect(
      destinations.map((d) => d.label),
      containsAll(['Commandes', 'Stock', 'Messages', 'Devis']),
    );
    expect(
      destinations.any((d) => d.requiresClinical),
      isFalse,
      reason: 'la pharmacie n\'a aucun accès clinique',
    );
  });

  test('le rôle pharmacien n\'ouvre pas l\'accès clinique', () {
    const session = AuthSession(
      kind: UserKind.pro,
      userId: 'me',
      role: ProRole.pharmacist,
    );
    expect(session.canAccessClinical, isFalse);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_data/nubia_data.dart';
import 'package:nubia_domain/nubia_domain.dart';

/// Invariants de cloisonnement du DI pharmacie (pattern du cloisonnement
/// clinique) : le stack tenant-pharmacie n'existe que dans l'app pharmacie,
/// le stack patient n'existe pas dans l'app pharmacie.
void main() {
  final gi = GetIt.instance;

  setUp(() async {
    await gi.reset();
    registerCore(gi);
  });

  tearDown(() async => gi.reset());

  test('registerData() par défaut → stack patient, PAS de stack pharmacie', () {
    registerData(gi);

    expect(gi.isRegistered<PatientPharmacyRepository>(), isTrue);
    expect(gi.isRegistered<PharmacyDirectoryRepository>(), isTrue);
    expect(gi.isRegistered<PharmacyOrderEventsPort>(), isTrue);
    expect(gi.isRegistered<PharmacyQuotesRepository>(), isTrue);

    expect(gi.isRegistered<PharmacyOrdersRepository>(), isFalse);
    expect(gi.isRegistered<StockRequestsRepository>(), isFalse);
    expect(gi.isRegistered<PharmacySessionRepository>(), isFalse);
    expect(gi<AuthInterceptor>().onTokensRefreshed, isNull,
        reason: 'seule l\'app pharmacie re-scope son token après refresh');
  });

  test(
      'includePharmacy: true → stack pharmacie, PAS de stack patient ni clinique',
      () {
    registerData(gi, includeClinical: false, includePharmacy: true);

    expect(gi.isRegistered<PharmacyOrdersRepository>(), isTrue);
    expect(gi.isRegistered<StockRequestsRepository>(), isTrue);
    expect(gi.isRegistered<PharmacyQuotesRepository>(), isTrue);
    expect(gi.isRegistered<CabinetMessageRepository>(), isTrue);
    expect(gi.isRegistered<PharmacyOrderEventsPort>(), isTrue);

    expect(gi.isRegistered<PharmacySessionRepository>(), isTrue);
    expect(gi<AuthInterceptor>().onTokensRefreshed, isNotNull,
        reason: 're-scope kind:"pharma" requis après chaque refresh');

    // Cloisonnement : pas d'accès clinique ni patient depuis l'app pharmacie.
    expect(gi.isRegistered<PrescriptionRepository>(), isFalse);
    expect(gi.isRegistered<ConsultationRepository>(), isFalse);
    expect(gi.isRegistered<PatientPharmacyRepository>(), isFalse);
  });

  test(
      'includePro: true → stock cabinet enregistré, pas de commandes pharmacie',
      () {
    registerData(gi, includeClinical: false, includePro: true);

    expect(gi.isRegistered<StockRequestsRepository>(), isTrue);
    expect(gi.isRegistered<PharmacyDirectoryRepository>(), isTrue);
    expect(gi.isRegistered<PharmacyOrdersRepository>(), isFalse);
  });

  test('l\'annuaire pharmacie est disponible dans toutes les configurations',
      () {
    registerData(gi, includeClinical: false);
    expect(gi.isRegistered<PharmacyDirectoryRepository>(), isTrue);
  });
}

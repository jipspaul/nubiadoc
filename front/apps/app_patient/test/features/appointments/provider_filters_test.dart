import 'package:flutter_test/flutter_test.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_patient/features/appointments/widgets/provider_filters_aside.dart';

// #5359 — panneau de filtres patient `.aside` : la maquette liste 4 groupes
// (Disponibilité, Consultation, Tarifs, Accessibilité) mais le point 6
// (verbatim) ne retient, comme « filtres qui comptent pour un patient »,
// que ceux qu'une vraie donnée `ProviderResult` permet de compter sans
// inventer de compteur (« à conserver » : jamais d'option sans compteur).
void main() {
  group('buildPatientFilterGroups', () {
    test('rend les 4 groupes de la maquette avec les libellés exacts', () {
      final groups = buildPatientFilterGroups();

      expect(groups.map((g) => g.title), [
        'Disponibilité',
        'Consultation',
        'Tarifs',
        'Accessibilité',
      ]);
      expect(
        groups.expand((g) => g.options.map((o) => o.label)),
        [
          'Sous 48 h',
          'Cette semaine',
          'Samedi',
          'Nouveaux patients',
          'Secteur 1',
          'Secteur 2',
          'Tiers payant',
          'Accès PMR',
        ],
      );
    });
  });

  group('filterProviders', () {
    final now = DateTime.now();
    final under48h = ProviderResult(
      id: 'p1',
      displayName: 'Dr Sous48h',
      specialty: 'Dentiste',
      nextSlotAt: now.add(const Duration(hours: 10)),
    );
    final farAway = ProviderResult(
      id: 'p2',
      displayName: 'Dr Loin',
      specialty: 'Dentiste',
      nextSlotAt: now.add(const Duration(days: 20)),
    );
    const sector1TiersPayant = ProviderResult(
      id: 'p3',
      displayName: 'Dr Secteur1',
      specialty: 'Dentiste',
      sector: '1',
      tiersPayant: true,
    );
    const sector2 = ProviderResult(
      id: 'p4',
      displayName: 'Dr Secteur2',
      specialty: 'Dentiste',
      sector: '2',
    );
    const pmrNewPatients = ProviderResult(
      id: 'p5',
      displayName: 'Dr PmrNouveaux',
      specialty: 'Dentiste',
      pmr: true,
      acceptsNewPatients: true,
    );

    final all = [
      under48h,
      farAway,
      sector1TiersPayant,
      sector2,
      pmrNewPatients,
    ];

    test('aucun filtre sélectionné -> renvoie la liste complète', () {
      expect(filterProviders(all, {}), all);
    });

    test('"Sous 48 h" ne garde que les prochains créneaux sous 48h', () {
      expect(filterProviders(all, {'under48h'}), [under48h]);
    });

    test('deux options du même groupe se combinent en OU', () {
      final result = filterProviders(all, {'sector1', 'sector2'});
      expect(
          result, containsAll(<ProviderResult>[sector1TiersPayant, sector2]));
      expect(result.length, 2);
    });

    test('des options de groupes différents se combinent en ET', () {
      expect(filterProviders(all, {'pmr', 'newPatients'}), [pmrNewPatients]);
    });

    test('"Tiers payant" ne garde que les praticiens qui le proposent', () {
      expect(filterProviders(all, {'tiersPayant'}), [sector1TiersPayant]);
    });

    test('un filtre sans aucune correspondance vide la liste (compteur 0)', () {
      expect(filterProviders(all, {'saturday'}).length,
          all.where((p) => p.nextSlotAt?.weekday == DateTime.saturday).length);
    });
  });
}

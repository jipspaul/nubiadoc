import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

Widget _wrap(Widget child) => MaterialApp(
      theme: NubiaTheme.light,
      home: Scaffold(body: Center(child: child)),
    );

void main() {
  group('ProviderCard', () {
    testWidgets('affiche nom, spécialité, dispo et distance', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const ProviderCard(
            name: 'Dr Claire Lefèvre',
            specialty: 'Chirurgien-dentiste',
            initials: 'CL',
            availabilityLabel: "1re dispo · Aujourd'hui",
            distance: '1,2 km',
            rppsVerified: true,
          ),
        ),
      );

      expect(find.text('Dr Claire Lefèvre'), findsOneWidget);
      expect(find.text('Chirurgien-dentiste'), findsOneWidget);
      expect(find.text("1re dispo · Aujourd'hui"), findsOneWidget);
      expect(find.text('1,2 km'), findsOneWidget);
      expect(find.byIcon(Icons.verified_rounded), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    });

    testWidgets('déclenche onTap au tap', (tester) async {
      var tapped = 0;
      await tester.pumpWidget(
        _wrap(
          ProviderCard(
            name: 'Dr Hugo Marin',
            specialty: 'Implantologie',
            initials: 'HM',
            onTap: () => tapped++,
          ),
        ),
      );

      await tester.tap(find.byType(ProviderCard));
      await tester.pumpAndSettle();
      expect(tapped, 1);
    });

    testWidgets(
        'affiche uniquement le nom, sans ligne résiduelle, quand la '
        'spécialité est vide (#3825)', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const ProviderCard(
            name: 'Dr Sarah Nguyen',
            specialty: '',
            initials: 'SN',
          ),
        ),
      );

      expect(find.text('Dr Sarah Nguyen'), findsOneWidget);
      expect(find.text(''), findsNothing);
    });

    testWidgets(
        'affiche le bloc « aucun créneau en ligne » avec accès à la fiche '
        'quand onViewProfile est fourni sans dispo (#5358)', (tester) async {
      var viewedProfile = 0;
      var cardTapped = 0;
      await tester.pumpWidget(
        _wrap(
          ProviderCard(
            name: 'Dr Sarah Nguyen',
            specialty: 'Chirurgien-dentiste',
            initials: 'SN',
            onTap: () => cardTapped++,
            onViewProfile: () => viewedProfile++,
          ),
        ),
      );

      expect(
        find.text('Aucun créneau en ligne pour ce praticien'),
        findsOneWidget,
      );
      expect(find.text('Voir sa fiche et ses coordonnées'), findsOneWidget);

      await tester.tap(find.byKey(const Key('no_online_slots_view_profile')));
      await tester.pumpAndSettle();
      expect(viewedProfile, 1);
      expect(cardTapped, 0);
    });

    testWidgets(
        'ne montre pas le bloc « aucun créneau en ligne » sans '
        'onViewProfile (repli neutre)', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const ProviderCard(
            name: 'Dr Sarah Nguyen',
            specialty: 'Chirurgien-dentiste',
            initials: 'SN',
          ),
        ),
      );

      expect(
        find.text('Aucun créneau en ligne pour ce praticien'),
        findsNothing,
      );
    });

    testWidgets(
        'affiche 3 jours de créneaux réels et déclenche onTap au clic sur '
        'une puce (#5357)', (tester) async {
      var tappedSlot = '';
      var viewedMore = 0;
      await tester.pumpWidget(
        _wrap(
          ProviderCard(
            name: 'Dr Rousseau',
            specialty: 'Chirurgien-dentiste',
            initials: 'DR',
            onViewMoreSlots: () => viewedMore++,
            daySlots: [
              ProviderResultDaySlots(
                dayLabel: 'Mar.',
                dateLabel: '11 août',
                chips: [
                  ProviderResultSlotChip(
                    label: '14:30',
                    onTap: () => tappedSlot = '14:30',
                  ),
                ],
              ),
              const ProviderResultDaySlots(
                dayLabel: 'Mer.',
                dateLabel: '12 août',
                chips: [],
              ),
              const ProviderResultDaySlots(
                dayLabel: 'Jeu.',
                dateLabel: '13 août',
                chips: [],
              ),
            ],
          ),
        ),
      );

      expect(find.text('Mar.'), findsOneWidget);
      expect(find.text('11 août'), findsOneWidget);
      expect(find.text('14:30'), findsOneWidget);
      expect(find.text('—'), findsNWidgets(2));
      expect(find.text('Voir plus de créneaux'), findsOneWidget);

      await tester.tap(find.text('14:30'));
      await tester.pumpAndSettle();
      expect(tappedSlot, '14:30');

      await tester.tap(find.byKey(const Key('provider_card_view_more_slots')));
      await tester.pumpAndSettle();
      expect(viewedMore, 1);
    });

    testWidgets('respecte la hauteur minimale de 84', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const SizedBox(
            width: 320,
            child: ProviderCard(name: 'X', specialty: 'Y', initials: 'XY'),
          ),
        ),
      );

      final size = tester.getSize(find.byType(ProviderCard));
      expect(size.height, greaterThanOrEqualTo(84));
    });
  });
}

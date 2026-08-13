import 'package:flutter_test/flutter_test.dart';
import 'package:nubia_domain/nubia_domain.dart';
import 'package:nubia_test_harness/nubia_test_harness.dart';

import 'package:app_pharmacie/features/order_detail/widgets/prescription_line_tile.dart';

void main() {
  testWidgets('ligne substituable sans générique affiche le tag Substituable',
      (tester) async {
    await tester.pumpApp(
      const PrescriptionLineTile(
        item: PrescriptionItem(
          label: 'Paracétamol 1 g',
          form: 'comprimé',
          posology: '1 cp jusqu\'à 3 fois par jour si douleur',
          duration: '',
          quantity: '8 comprimés',
        ),
      ),
    );

    expect(find.text('Substituable'), findsOneWidget);
    expect(find.textContaining('Générique délivré'), findsNothing);
    expect(find.textContaining('Non substituable'), findsNothing);
  });

  testWidgets('ligne substituable avec générique délivré affiche les deux tags',
      (tester) async {
    await tester.pumpApp(
      const PrescriptionLineTile(
        item: PrescriptionItem(
          label: 'Amoxicilline 1 g',
          form: 'comprimé dispersible',
          posology: '1 comprimé matin et soir',
          duration: '7 jours',
          quantity: '14 comprimés',
          dispensedGeneric: 'Amoxicilline Biogaran',
        ),
      ),
    );

    expect(find.text('Substituable'), findsOneWidget);
    expect(
      find.text('Générique délivré : Amoxicilline Biogaran'),
      findsOneWidget,
    );
  });

  testWidgets('ligne non substituable affiche le tag Non substituable — MTE',
      (tester) async {
    await tester.pumpApp(
      const PrescriptionLineTile(
        item: PrescriptionItem(
          label: 'Chlorhexidine 0,12 %',
          form: 'bain de bouche',
          posology: '2 bains de bouche par jour après les repas',
          duration: '10 jours',
          quantity: '1 flacon 300 ml',
          substitutable: false,
        ),
      ),
    );

    expect(find.text('Non substituable — MTE'), findsOneWidget);
    expect(find.text('Substituable'), findsNothing);
  });
}

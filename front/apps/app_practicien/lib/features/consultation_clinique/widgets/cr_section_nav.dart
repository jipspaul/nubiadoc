// Quoi : navigation latérale des sections du formulaire de CR opératoire
// (#7153) — une entrée par section (diagnostic, chirurgie, endodontie,
// parodontologie, suites opératoires), section active surlignée.
// Quand : rendue par `CrOperatoireFormPage`, à gauche du corps du
// formulaire.
// Pourquoi : extrait du fichier principal pour rester sous le plafond de
// taille (même logique que `side_column.dart`/`acts_of_session_card.dart`,
// #4954).
// Modes d'échec : aucun — liste statique de sections, purement
// présentationnelle.
import 'package:flutter/material.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

class CrSectionDef {
  const CrSectionDef(this.key, this.title);

  final String key;
  final String title;
}

/// Sections d'un CR opératoire (#7153) — couvre les trois types d'actes
/// visés par la maquette (chirurgie, endodontie, parodontologie),
/// encadrés par un diagnostic et des suites opératoires.
const List<CrSectionDef> kCrSectionDefs = [
  CrSectionDef('diagnostic', 'Diagnostic'),
  CrSectionDef('chirurgie', 'Chirurgie'),
  CrSectionDef('endodontie', 'Endodontie'),
  CrSectionDef('parodontologie', 'Parodontologie'),
  CrSectionDef('suites_operatoires', 'Suites opératoires'),
];

class CrSectionNav extends StatelessWidget {
  const CrSectionNav({
    super.key,
    required this.selectedKey,
    required this.onSelect,
  });

  final String selectedKey;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListView(
      key: const Key('cr_section_nav'),
      padding: EdgeInsets.zero,
      children: [
        for (final def in kCrSectionDefs)
          Container(
            color: def.key == selectedKey ? cs.primaryContainer : null,
            child: ListRow(
              key: Key('cr_section_nav_${def.key}'),
              title: def.title,
              showDivider: false,
              onTap: () => onSelect(def.key),
            ),
          ),
      ],
    );
  }
}

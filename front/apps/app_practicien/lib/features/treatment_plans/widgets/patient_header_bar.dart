//! Bandeau patient (#5024, maquette design-v2 §.hd) : retour + avatar à
//! initiales + nom + sous-titre + libellé d'écran aligné à droite.
//! Remplace l'AppBar générique « Plans de traitement » en tête de
//! `TreatmentPlansPage`.
//!
//! Identité patient : [PatientHeaderCubit] (nom, date de naissance) —
//! `null` tant qu'elle n'est pas chargée, le bandeau affiche alors un nom
//! générique plutôt que de bloquer l'affichage du reste de l'écran.
//!
//! Le « référent » de la maquette (praticien qui suit le patient) n'a pas
//! de source de données dans `CabinetPatient` à ce jour — segment omis
//! plutôt que fabriqué (dépendance données non résolue, cf. #5024).

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import '../patient_header_cubit.dart';

class PatientHeaderBar extends StatelessWidget {
  const PatientHeaderBar({super.key, required this.trailingLabel});

  final String trailingLabel;

  @override
  Widget build(BuildContext context) {
    final patient = context.watch<PatientHeaderCubit>().state;
    final cs = Theme.of(context).colorScheme;
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    final textTheme = Theme.of(context).textTheme;
    final name =
        patient != null && patient.fullName.isNotEmpty ? patient.fullName : 'Patient';
    final subtitle = _subtitle(patient);

    return Container(
      key: const Key('treatment_plans_header'),
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(bottom: BorderSide(color: tokens.borderSubtle)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: Row(
        children: [
          IconButton(
            key: const Key('treatment_plans_back_button'),
            icon: const Icon(Icons.arrow_back),
            tooltip: 'Retour',
            onPressed: () => Navigator.of(context).pop(),
          ),
          NubiaAvatar(initials: initialsFrom(name), radius: 18),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  style: textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
                if (subtitle != null)
                  Text(
                    subtitle,
                    style: textTheme.bodySmall
                        ?.copyWith(color: cs.onSurfaceVariant),
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(trailingLabel, style: textTheme.titleMedium),
        ],
      ),
    );
  }

  String? _subtitle(CabinetPatient? patient) {
    final birthDate = patient?.birthDate;
    if (birthDate == null) return null;
    return '${_age(birthDate)} ans';
  }
}

/// Âge en années révolues à partir d'une date de naissance (heure locale) —
/// même calcul que `PatientIdentityBar._age` (consultation_clinique).
int _age(DateTime birthDate) {
  final now = DateTime.now();
  final d = birthDate.toLocal();
  var age = now.year - d.year;
  if (now.month < d.month || (now.month == d.month && now.day < d.day)) {
    age--;
  }
  return age;
}

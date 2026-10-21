import 'package:flutter/material.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

/// Texte des CGU acceptées à l'inscription (`signup_cubit.dart`, `cguVersion:
/// '1.0'`) : avant ce fix, la case à cocher de /signup faisait accepter une
/// version versionnée côté serveur sans qu'aucune page ne permette de la lire
/// (#6801). Version affichée ici = celle réellement envoyée à l'API.
class CguPage extends StatelessWidget {
  const CguPage({super.key});

  static const _version = '1.0';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<NubiaTokens>();

    return Scaffold(
      key: const Key('cgu_scaffold'),
      appBar: AppBar(title: const Text("Conditions Générales d'Utilisation")),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Version $_version',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: tokens?.textTertiary),
                ),
                const SizedBox(height: 16),
                Text('1. Objet', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                Text(
                  "Les présentes Conditions Générales d'Utilisation régissent "
                  "l'accès et l'usage de l'application Nubia par le patient, "
                  'notamment la prise de rendez-vous, la gestion de son '
                  'dossier médical et les échanges avec les cabinets '
                  "partenaires.",
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                Text('2. Compte utilisateur', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                Text(
                  "La création d'un compte requiert une adresse e-mail valide "
                  'et un mot de passe. Le patient est responsable de la '
                  'confidentialité de ses identifiants et des actions '
                  'réalisées depuis son compte.',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                Text('3. Données personnelles', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                Text(
                  'Le traitement des données de santé et personnelles du '
                  'patient est détaillé dans l\'écran « Mes consentements », '
                  'accessible depuis le profil une fois le compte créé : '
                  'finalités, bases légales et droits RGPD y sont présentés '
                  'individuellement.',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                Text('4. Responsabilité', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                Text(
                  "Nubia met à disposition un outil de mise en relation et de "
                  "suivi avec des professionnels de santé. Les actes de soin "
                  "et les décisions médicales relèvent de la seule "
                  "responsabilité du praticien.",
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                Text('5. Droit applicable', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                Text(
                  'Les présentes CGU sont soumises au droit français.',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

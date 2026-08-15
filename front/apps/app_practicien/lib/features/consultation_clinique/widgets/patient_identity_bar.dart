// Quoi : barre d'identité patient en tête de l'écran consultation au
// fauteuil (avatar, nom, statut de séance, recherche globale, total de
// séance, bouton « Terminer »).
// Quand : rendue par `_LoadedView` (`consultation_clinique_page.dart`), en
// premier enfant de la colonne, avant les colonnes centre/côté/contexte.
// Pourquoi : extrait de `consultation_clinique_page.dart` (#4954) pour
// redescendre ce fichier sous le plafond de taille CLAUDE.md — aucun
// changement de rendu, mêmes Keys (`patient_identity_bar`,
// `global_search_field`, `consultation_session_total`,
// `complete_consultation_button`).
// Modes d'échec : aucun — widget purement présentationnel ; `onCompletePressed`
// null désactive le bouton « Terminer » (séance déjà terminée ou action en
// cours), décidé par l'appelant.
import 'package:flutter/material.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'consultation_format_utils.dart';
import 'consultation_layout_breakpoints.dart';

/// Barre d'identité patient (#4945/#4946/#4948) : avatar + nom + statut de
/// séance, recherche globale (à partir de [kTwoColumnBreakpoint] de largeur
/// *disponible*, jamais `MediaQuery`, cf. #4935), total de séance et bouton
/// « Terminer ».
class PatientIdentityBar extends StatelessWidget {
  const PatientIdentityBar({
    super.key,
    required this.session,
    required this.textTheme,
    required this.globalSearchFocusNode,
    required this.onCompletePressed,
  });

  final ClinicalSession session;
  final TextTheme textTheme;
  // #4948 — focus partagé avec la recherche d'acte CCAM du volet droit.
  final FocusNode globalSearchFocusNode;
  final VoidCallback? onCompletePressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: NubiaCard(
        key: const Key('patient_identity_bar'),
        // #4948 — la recherche globale ne s'affiche qu'à partir de la
        // largeur *disponible* de la barre (jamais MediaQuery, cf. #4935) :
        // sous ce seuil elle écraserait l'identité patient.
        child: LayoutBuilder(
          builder: (context, constraints) {
            final showGlobalSearch =
                constraints.maxWidth >= kTwoColumnBreakpoint;
            return Row(
              children: [
                NubiaAvatar(
                  initials: _patientInitials(session.patientName),
                  radius: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              session.patientName?.trim().isNotEmpty == true
                                  ? session.patientName!.trim()
                                  : 'Patient',
                              style: textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w600),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          StatusPill(
                            label: session.isCancelled
                                ? 'Annulée'
                                : session.isCompleted
                                    ? 'Terminée'
                                    : 'Séance en cours',
                            variant: session.isCancelled
                                ? StatusPillVariant.warning
                                : session.isCompleted
                                    ? StatusPillVariant.success
                                    : StatusPillVariant.info,
                            icon: session.isCancelled || session.isCompleted
                                ? null
                                : Icons.info_outline,
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      _PatientIdentitySubtitle(
                        birthDate: session.patientBirthDate,
                        lastVisitDate: session.lastVisitDate,
                        practitionerName: session.practitionerName,
                        textTheme: textTheme,
                      ),
                    ],
                  ),
                ),
                if (showGlobalSearch) ...[
                  const SizedBox(width: 12),
                  // #4948 — recherche globale centrée entre l'identité
                  // patient et le total : partage le focus ⌘K avec la
                  // recherche d'acte CCAM du volet droit (pas de recherche
                  // transverse pour l'instant, voir `_GlobalSearchField`).
                  Expanded(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 360),
                        child: _GlobalSearchField(
                          key: const Key('global_search_field'),
                          focusNode: globalSearchFocusNode,
                        ),
                      ),
                    ),
                  ),
                ],
                const SizedBox(width: 12),
                _SessionTotal(
                  // #3402 — même calcul que le total transmis au POST
                  // .../acts : somme des `amountCents` des actes enregistrés.
                  totalCents: sessionTotalCents(session),
                  textTheme: textTheme,
                ),
                const SizedBox(width: 12),
                NubiaButton(
                  key: const Key('complete_consultation_button'),
                  size: NubiaButtonSize.sm,
                  icon: Icons.check,
                  label: 'Terminer',
                  onPressed: onCompletePressed,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Sous-titre de la barre d'identité patient (#4945, #4956) — « âge ans ·
/// né(e) le JJ/MM/AAAA · Dernière visite JJ/MM · Dr praticien ». N'affiche
/// que les segments dont la donnée est disponible (ex. date de naissance ou
/// dernière visite absentes du dossier patient).
class _PatientIdentitySubtitle extends StatelessWidget {
  const _PatientIdentitySubtitle({
    required this.birthDate,
    required this.lastVisitDate,
    required this.practitionerName,
    required this.textTheme,
  });

  final DateTime? birthDate;
  final DateTime? lastVisitDate;
  final String? practitionerName;
  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    final practitioner = practitionerName?.trim();
    final parts = <String>[
      if (birthDate != null) '${_age(birthDate!)} ans',
      if (birthDate != null) 'né(e) le ${_formatBirthDate(birthDate!)}',
      if (lastVisitDate != null)
        'Dernière visite ${_formatLastVisit(lastVisitDate!)}',
      if (practitioner != null && practitioner.isNotEmpty) 'Dr $practitioner',
    ];
    if (parts.isEmpty) return const SizedBox.shrink();
    return Text(
      parts.join(' · '),
      style: textTheme.bodySmall?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}

/// Total de la séance, barre d'identité patient (#4946) : libellé « TOTAL
/// SÉANCE » en capitales grises + montant en chiffres tabulaires, aligné à
/// droite juste avant le bouton « Terminer ». Réutilise le formateur euros
/// commun du design system ([formatQuoteCents]) pour rester cohérent avec le
/// reste de l'app.
class _SessionTotal extends StatelessWidget {
  const _SessionTotal({required this.totalCents, required this.textTheme});

  final int totalCents;
  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const Key('consultation_session_total'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          'TOTAL SÉANCE',
          style: textTheme.labelSmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        Text(
          formatQuoteCents(totalCents, alwaysShowDecimals: true),
          style: textTheme.headlineSmall?.copyWith(
            fontFeatures: tabularFigures,
          ),
        ),
      ],
    );
  }
}

/// Recherche globale de la barre du haut (#4948, maquette `.kb`) : encart
/// bordé, icône loupe, texte grisé « Acte, patient, ordonnance… » et badge
/// clavier ⌘K, centré entre l'identité patient et le total.
///
/// Distinct de la recherche d'acte du volet droit (`ccam_search_field`) —
/// en l'absence de recherche transverse (patient/ordonnance), un tap ici
/// place le focus sur cette même recherche d'acte, comme le raccourci ⌘K
/// (#4941) : le tooltip marque explicitement ce périmètre restreint.
class _GlobalSearchField extends StatelessWidget {
  const _GlobalSearchField({super.key, required this.focusNode});

  final FocusNode focusNode;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    final textTheme = Theme.of(context).textTheme;
    return Tooltip(
      message: 'Recherche d\'actes pour l\'instant — '
          'patient et ordonnance à venir',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: focusNode.requestFocus,
          child: Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: tokens.borderDefault),
            ),
            child: Row(
              children: [
                Icon(Icons.search, size: 18, color: tokens.textTertiary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Acte, patient, ordonnance…',
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodyMedium
                        ?.copyWith(color: tokens.textTertiary),
                  ),
                ),
                const SizedBox(width: 8),
                const _GlobalSearchShortcutBadge(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Badge « ⌘K » (#4948) — même style que `_CcamShortcutBadge`
/// (ccam_picker.dart, #4941) et `_SearchShortcutHint` (orders_page.dart).
class _GlobalSearchShortcutBadge extends StatelessWidget {
  const _GlobalSearchShortcutBadge();

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: tokens.borderSubtle,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: tokens.borderDefault),
      ),
      child: Text(
        '⌘K',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: tokens.textTertiary,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

/// Initiales (max 2 lettres) du patient pour l'avatar de la barre d'identité
/// (#4945) — même convention que `waiting_room_page.dart::_initials`.
String _patientInitials(String? patientName) {
  final name = patientName?.trim() ?? '';
  final parts = name.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
  return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
      .toUpperCase();
}

/// Âge en années révolues à partir d'une date de naissance (heure locale).
int _age(DateTime birthDate) {
  final now = DateTime.now();
  final d = birthDate.toLocal();
  var age = now.year - d.year;
  if (now.month < d.month || (now.month == d.month && now.day < d.day)) {
    age--;
  }
  return age;
}

/// Date de naissance JJ/MM/AAAA (heure locale) — format imposé par la
/// maquette design-v2 pour la barre d'identité patient (#4945).
String _formatBirthDate(DateTime dt) {
  final d = dt.toLocal();
  final dd = d.day.toString().padLeft(2, '0');
  final mm = d.month.toString().padLeft(2, '0');
  return '$dd/$mm/${d.year}';
}

/// Dernière visite JJ/MM (heure locale) — format imposé par la maquette
/// design-v2 pour la barre d'identité patient (#4956).
String _formatLastVisit(DateTime dt) {
  final d = dt.toLocal();
  final dd = d.day.toString().padLeft(2, '0');
  final mm = d.month.toString().padLeft(2, '0');
  return '$dd/$mm';
}

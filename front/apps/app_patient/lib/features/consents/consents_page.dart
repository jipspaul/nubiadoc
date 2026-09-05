import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'consents_cubit.dart';

/// Sous-titre compteur de l'en-tête (maquette design-v2,
/// `patient-consentements.png`, #5207) : « N accordés · N refusés » dérivé
/// de `consent.granted`. Une finalité verrouillée base-légale toujours ON
/// compte comme accordée, jamais comme refusée.
String _consentsSubtitle(List<Consent> consents) {
  final grantedCount = consents.where((c) => c.granted).length;
  final refusedCount = consents.length - grantedCount;
  return '$grantedCount accordés · $refusedCount refusés';
}

// #5214 — nom du cabinet responsable et e-mail DPO ne sont exposés nulle
// part côté patient (ni `ConsentsLoaded`, ni `patient_di.dart`, ni aucune
// config de session) : pas de champ à lire tant que l'API/session cabinet
// n'expose pas ces informations. TODO(#5214) : remplacer par la config du
// cabinet dès qu'elle est exposée au front patient.
const _kDataControllerName = 'Cabinet Nubia Opéra';
const _kDpoEmail = 'dpo@nubia.fr';

/// Libellés lisibles des finalités RGPD connues (fallback = purpose brut).
// Doit couvrir exactement les finalités émises par l'API (api/src/auth/mod.rs,
// db/migrations/0008_audit_consent.sql) — un écart ici affiche la clé brute
// en snake_case à l'utilisateur sur un écran RGPD (#3706). `research` et
// `third_party_sharing` ne sont émises par aucun endpoint : retirées.
const _kConsentLabels = <String, String>{
  'data_processing': 'Traitement de mes données de santé',
  'marketing': 'Communications marketing',
  'soins': 'Soins',
  'partage_pharmacie': 'Partage avec ma pharmacie',
  'partage_confrere': 'Partage avec un confrère',
  'ia_scribe': 'Assistance IA (scribe)',
};

/// Libellé affiché quand `purpose` n'a pas d'entrée dans [_kConsentLabels] :
/// jamais la clé technique brute (snake_case) sur cet écran RGPD.
const _kUnknownConsentLabel = 'Finalité non documentée — contactez le cabinet';

/// Phrases « qui accède à quoi, pour quoi faire » par finalité (maquette
/// design-v2, `patient-consentements.png`, #5208) : le libellé seul
/// n'informe pas — exigence de consentement éclairé. Verbatim maquette,
/// même contrainte de couverture que [_kConsentLabels] (#3706) : doit
/// couvrir exactement les mêmes finalités, testé en comparant les deux
/// jeux de clés.
const _kConsentDescriptions = <String, String>{
  'data_processing':
      'Conservation sécurisée de votre dossier chez un hébergeur agréé '
          'données de santé, en France.',
  'marketing': 'Nouveautés du cabinet, offres de prévention. Sans effet sur '
      'vos rappels de rendez-vous.',
  'soins': 'Votre praticien enregistre les actes réalisés et son '
      'compte-rendu dans votre dossier médical.',
  'partage_pharmacie':
      'Vos ordonnances sont transmises à la pharmacie que vous avez '
          'choisie, pour préparation avant votre passage.',
  'partage_confrere':
      "Un autre praticien peut consulter votre dossier s'il vous prend en "
          'charge — second avis, urgence, remplacement.',
  'ia_scribe': 'Votre praticien peut dicter son compte-rendu ; une IA le '
      "met en forme. L'enregistrement n'est pas conservé.",
};

/// Seule finalité dont le retrait passe par une feuille de confirmation
/// (maquette design-v2, #5211/#5212) : les autres bascules restent
/// immédiates, comme avant.
const _kPharmacySharingPurpose = 'partage_pharmacie';

/// Base légale des finalités librement révocables (à l'opposé de
/// [_kLockedConsentPurposes], dont la base légale est le contrat de soin),
/// affichée par la feuille de détail d'un consentement (#6478).
const _kConsentBasedLegalBasis = 'Consentement (article 6.1.a du RGPD) — '
    'vous pouvez le retirer à tout moment.';

/// Statut daté d'un consentement (maquette design-v2, #5210 : le RGPD
/// impose de pouvoir prouver la date du consentement, pas seulement son état
/// actuel). Partagé entre [_ConsentMetaRow] et [_ConsentDetailsSheet] (#6478)
/// pour que les deux affichages restent cohérents.
({String label, IconData icon}) _consentStatus(Consent consent) {
  if (consent.granted) {
    return (
      label: consent.grantedAt != null
          ? 'Accordé le ${NubiaDate.dayLong(consent.grantedAt)}'
          : 'Accordé',
      icon: Icons.check_circle,
    );
  }
  if (consent.revokedAt != null) {
    return (
      label: 'Refusé le ${NubiaDate.dayLong(consent.revokedAt)}',
      icon: Icons.cancel,
    );
  }
  return (label: 'Jamais accordé', icon: Icons.cancel);
}

/// Regroupement des finalités librement révocables en sections « Partages »,
/// « Technologies », « Communications » (maquette design-v2,
/// `patient-consentements.png`, #5204). La section « Nécessaire au service »
/// est gérée séparément, voir [_kLockedConsentPurposes].
class _ConsentSectionDef {
  const _ConsentSectionDef({required this.title, this.badge, required this.purposes});

  final String title;
  final String? badge;
  final List<String> purposes;
}

/// Titre du groupe par défaut d'une finalité émise par l'API mais absente de
/// [_kConsentSections] : visible plutôt que masquée (critère d'acceptation
/// #5204).
const _kDefaultConsentSectionTitle = 'Autres';

const _kConsentSections = <_ConsentSectionDef>[
  _ConsentSectionDef(
    title: 'Partages',
    badge: 'vous décidez',
    purposes: ['partage_pharmacie', 'partage_confrere'],
  ),
  _ConsentSectionDef(
    title: 'Technologies',
    purposes: ['ia_scribe'],
  ),
  _ConsentSectionDef(
    title: 'Communications',
    purposes: ['marketing'],
  ),
];

/// Icône ronde à gauche de chaque carte de finalité (maquette design-v2,
/// #5204). Fallback générique pour une finalité non couverte plutôt qu'une
/// icône trompeuse.
const _kConsentIcons = <String, IconData>{
  'partage_pharmacie': Icons.local_pharmacy_outlined,
  'partage_confrere': Icons.groups_outlined,
  'ia_scribe': Icons.smart_toy_outlined,
  'marketing': Icons.campaign_outlined,
};
const _kDefaultConsentIcon = Icons.privacy_tip_outlined;

/// Répartit [consents] dans les sections de [_kConsentSections], dans
/// l'ordre déclaré, puis regroupe tout ce qui n'y est pas mappé sous
/// [_kDefaultConsentSectionTitle] (jamais masqué).
List<({String title, String? badge, List<Consent> consents})>
    _groupConsentsBySection(List<Consent> consents) {
  final byPurpose = {for (final c in consents) c.purpose: c};
  final assigned = <String>{};
  final sections = <({String title, String? badge, List<Consent> consents})>[];

  for (final def in _kConsentSections) {
    final matched = [
      for (final purpose in def.purposes)
        if (byPurpose[purpose] case final consent?) consent,
    ];
    assigned.addAll(def.purposes);
    if (matched.isNotEmpty) {
      sections.add((title: def.title, badge: def.badge, consents: matched));
    }
  }

  final leftover =
      consents.where((c) => !assigned.contains(c.purpose)).toList();
  if (leftover.isNotEmpty) {
    sections.add(
      (title: _kDefaultConsentSectionTitle, badge: null, consents: leftover),
    );
  }
  return sections;
}

/// Finalités dont la base légale n'est pas le consentement révocable mais
/// l'exécution du contrat de soin (maquette design-v2, groupe « Nécessaire
/// au service », #5205) : bascule verrouillée (ON, non actionnable) plutôt
/// qu'au même rang qu'une finalité comme le marketing.
/// ⚠️ Mapping proposé, pas une vérité juridique tranchée — la distinction
/// « nécessaire au service » / « optionnel » doit être validée par le DPO
/// (le modèle `Consent` ne porte pas cette info). Regroupé ici en un seul
/// endroit explicite pour rester facile à faire évoluer si le DPO change
/// le périmètre, sans creuser dans l'arbre de widgets.
const _kLockedConsentPurposes = <String, String>{
  'soins': 'Requis pour être soigné',
  'data_processing': 'Base légale : exécution du contrat',
};

/// Bascule un consentement — sauf le retrait du partage pharmacie, qui
/// passe d'abord par une feuille de confirmation (#5211) signalant le cas
/// particulier d'une commande déjà transmise (#5212).
void _handleToggle(BuildContext context, String purpose, bool granted) {
  if (purpose == _kPharmacySharingPurpose && !granted) {
    final cubit = context.read<ConsentsCubit>();
    NubiaBottomSheet.show<void>(
      context: context,
      child: BlocProvider.value(
        value: cubit,
        child: const _PharmacyWithdrawalSheet(),
      ),
    );
    return;
  }
  context.read<ConsentsCubit>().toggle(purpose, granted);
}

class ConsentsPage extends StatelessWidget {
  const ConsentsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => GetIt.instance<ConsentsCubit>()..load(),
      child: Scaffold(
        appBar: AppBar(
          title: BlocBuilder<ConsentsCubit, ConsentsState>(
            builder: (context, state) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Mes consentements'),
                  if (state is ConsentsLoaded)
                    Text(
                      _consentsSubtitle(state.consents),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              );
            },
          ),
        ),
        body: const _ConsentsBody(),
      ),
    );
  }
}

class _ConsentsBody extends StatelessWidget {
  const _ConsentsBody();

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<ConsentsCubit, ConsentsState>(
      listenWhen: (_, s) =>
          s is ConsentsError || (s is ConsentsLoaded && s.toggleError != null),
      listener: (context, state) {
        final message = switch (state) {
          ConsentsError(:final message) => message,
          ConsentsLoaded(:final toggleError?) => toggleError,
          _ => null,
        };
        if (message != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(message)),
          );
        }
      },
      builder: (context, state) {
        if (state is ConsentsLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        if (state is ConsentsError) {
          return NubiaErrorWidget(
            message: state.message,
            onRetry: () => context.read<ConsentsCubit>().load(),
          );
        }
        if (state is ConsentsLoaded) {
          if (state.consents.isEmpty) {
            return const NubiaEmptyState(
              key: Key('consents_empty'),
              icon: Icons.verified_user_outlined,
              title: 'Aucun consentement à gérer',
            );
          }
          final lockedConsents = state.consents
              .where((c) => _kLockedConsentPurposes.containsKey(c.purpose))
              .toList();
          final otherConsents = state.consents
              .where((c) => !_kLockedConsentPurposes.containsKey(c.purpose))
              .toList();
          final otherSections = _groupConsentsBySection(otherConsents);

          return ListView(
            key: const Key('consents_list'),
            children: [
              const _ConsentsIntroBanner(),
              if (lockedConsents.isNotEmpty)
                _LockedConsentsSection(consents: lockedConsents),
              for (final section in otherSections)
                _ConsentSection(
                  title: section.title,
                  badge: section.badge,
                  consents: section.consents,
                  pharmacyName: state.pharmacyName,
                  pendingPurpose: state.pending,
                ),
              const _ConsentsFooter(),
              const _RightsSection(),
            ],
          );
        }
        return const SizedBox.shrink();
      },
    );
  }
}

/// Bandeau explicatif RGPD en tête de liste (maquette design-v2,
/// `patient-consentements.png`, `.intro`, #5206) : reprend la formulation
/// RGPD d'origine (« modifiable à tout moment », « prend effet
/// immédiatement ») dans une carte à icône bouclier plutôt qu'un simple
/// texte.
class _ConsentsIntroBanner extends StatelessWidget {
  const _ConsentsIntroBanner();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      key: const Key('consents_intro_banner'),
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: NubiaColors.n0,
        border: Border.all(color: NubiaColors.n200),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.shield, color: NubiaColors.brand700),
          const SizedBox(width: 12),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: NubiaColors.n700),
                children: const [
                  TextSpan(
                    text: 'Vous décidez de ce que Nubia peut faire de vos '
                        'données. ',
                  ),
                  TextSpan(
                    text: 'Chaque choix est modifiable à tout moment',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: NubiaColors.n900,
                    ),
                  ),
                  TextSpan(
                    text: ' et prend effet immédiatement.',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Section « Nécessaire au service » (maquette design-v2,
/// `patient-consentements.png`, #5205) : regroupe les finalités dont la
/// base légale n'est pas le consentement révocable ([_kLockedConsentPurposes])
/// sous un en-tête + badge « Non modifiable », séparément des bascules
/// librement révocables (marketing, partage, ia_scribe…).
class _LockedConsentsSection extends StatelessWidget {
  const _LockedConsentsSection({required this.consents});

  final List<Consent> consents;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<NubiaTokens>()!;

    return Padding(
      key: const Key('consents_locked_section'),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Nécessaire au service',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: 8),
              Container(
                key: const Key('consents_locked_badge'),
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: tokens.neutralBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'Non modifiable',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: tokens.neutralFg,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (final consent in consents) ...[
            _LockedConsentCard(
              key: Key('consent_card_${consent.purpose}'),
              consent: consent,
              legalBasisLabel: _kLockedConsentPurposes[consent.purpose]!,
            ),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

/// Carte `.cc.req` d'une finalité verrouillée (maquette design-v2, #5205) :
/// fond `--n50`, bord `--n300`, icône grise, bascule `on lock` (ON,
/// `onChanged: null` — ne réagit pas au tap) et puce `.reqp` énonçant la
/// base légale.
class _LockedConsentCard extends StatelessWidget {
  const _LockedConsentCard({
    super.key,
    required this.consent,
    required this.legalBasisLabel,
  });

  final Consent consent;
  final String legalBasisLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<NubiaTokens>()!;

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: NubiaColors.n50,
        border: Border.all(color: NubiaColors.n300),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 12, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.lock_outline, color: NubiaColors.n400),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _kConsentLabels[consent.purpose] ??
                            _kUnknownConsentLabel,
                        style: theme.textTheme.titleSmall,
                      ),
                      if (_kConsentDescriptions[consent.purpose]
                          case final description?) ...[
                        const SizedBox(height: 4),
                        Text(
                          description,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: tokens.neutralFg),
                        ),
                      ],
                    ],
                  ),
                ),
                Semantics(
                  container: true,
                  label: _kConsentLabels[consent.purpose] ??
                      _kUnknownConsentLabel,
                  child: Switch(
                    key: Key('consent_${consent.purpose}'),
                    value: true,
                    onChanged: null,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                key: Key('consent_required_pill_${consent.purpose}'),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: tokens.neutralBg,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.lock, size: 14, color: tokens.neutralFg),
                    const SizedBox(width: 6),
                    Text(
                      legalBasisLabel,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: tokens.neutralFg,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          _ConsentMetaRow(consent: consent, legalBasis: legalBasisLabel),
        ],
      ),
    );
  }
}

/// Section groupée d'une des finalités librement révocables (« Partages »,
/// « Technologies », « Communications », maquette design-v2, #5204) : en-tête
/// `.gh` + badge optionnel, suivi des cartes `.cc` de chaque finalité du
/// groupe.
class _ConsentSection extends StatelessWidget {
  const _ConsentSection({
    required this.title,
    this.badge,
    required this.consents,
    required this.pharmacyName,
    required this.pendingPurpose,
  });

  final String title;
  final String? badge;
  final List<Consent> consents;
  final String? pharmacyName;
  final String? pendingPurpose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<NubiaTokens>()!;

    return Padding(
      key: Key('consents_section_$title'),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                title,
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              if (badge case final badgeLabel?) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: tokens.primarySubtleBg,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    badgeLabel,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: tokens.primarySubtleFg,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          for (final consent in consents) ...[
            _ConsentCard(
              consent: consent,
              pharmacyName: pharmacyName,
              pending: pendingPurpose == consent.purpose,
            ),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

/// Carte `.cc` d'une finalité librement révocable (maquette design-v2,
/// #5204) : fond blanc, bord `--n200`, rayon 14, icône ronde à gauche, titre
/// + description, bascule à droite.
class _ConsentCard extends StatelessWidget {
  const _ConsentCard({
    required this.consent,
    required this.pharmacyName,
    required this.pending,
  });

  final Consent consent;
  final String? pharmacyName;
  final bool pending;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<NubiaTokens>()!;

    return Container(
      key: Key('consent_card_${consent.purpose}'),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: NubiaColors.n0,
        border: Border.all(color: NubiaColors.n200),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 12, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: tokens.primarySubtleBg,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Icon(
                      _kConsentIcons[consent.purpose] ?? _kDefaultConsentIcon,
                      color: tokens.primarySubtleFg,
                      size: 20,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _kConsentLabels[consent.purpose] ??
                            _kUnknownConsentLabel,
                        style: theme.textTheme.titleSmall,
                      ),
                      if (_kConsentDescriptions[consent.purpose]
                          case final description?) ...[
                        const SizedBox(height: 4),
                        Text(
                          description,
                          key: Key('consent_description_${consent.purpose}'),
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: tokens.neutralFg),
                        ),
                      ],
                    ],
                  ),
                ),
                Semantics(
                  container: true,
                  label: _kConsentLabels[consent.purpose] ??
                      _kUnknownConsentLabel,
                  child: Switch(
                    key: Key('consent_${consent.purpose}'),
                    value: consent.granted,
                    onChanged: pending
                        ? null
                        : (v) => _handleToggle(context, consent.purpose, v),
                  ),
                ),
              ],
            ),
          ),
          if (consent.purpose == _kPharmacySharingPurpose)
            _PharmacyRecipientChip(pharmacyName: pharmacyName),
          _ConsentMetaRow(
            consent: consent,
            legalBasis: _kConsentBasedLegalBasis,
            recipientName: consent.purpose == _kPharmacySharingPurpose
                ? pharmacyName
                : null,
          ),
        ],
      ),
    );
  }
}

/// Ligne méta « statut daté » d'un consentement (maquette design-v2,
/// `patient-consentements.png`, #5210) : le RGPD impose de pouvoir prouver
/// la date du consentement, pas seulement son état actuel (accordé/refusé).
class _ConsentMetaRow extends StatelessWidget {
  const _ConsentMetaRow({
    required this.consent,
    required this.legalBasis,
    this.recipientName,
  });

  final Consent consent;

  /// Base légale affichée par la feuille de détail (#6478) — contrat de
  /// soin pour les finalités verrouillées, consentement pour les autres.
  final String legalBasis;

  /// Destinataire connu de cette finalité (ex. pharmacie déclarée pour
  /// `partage_pharmacie`), affiché par la feuille de détail si présent.
  final String? recipientName;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    final textStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
          color: tokens.textTertiary,
        );
    final status = _consentStatus(consent);

    return Container(
      key: Key('consent_meta_${consent.purpose}'),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: tokens.borderSubtle)),
      ),
      child: Row(
        children: [
          Icon(status.icon, size: 16, color: tokens.textTertiary),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              status.label,
              style: textStyle,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Semantics(
            button: true,
            label: 'Détails',
            container: true,
            child: GestureDetector(
              key: Key('consent_details_${consent.purpose}'),
              onTap: () => NubiaBottomSheet.show<void>(
                context: context,
                child: _ConsentDetailsSheet(
                  consent: consent,
                  legalBasis: legalBasis,
                  recipientName: recipientName,
                ),
              ),
              child: ExcludeSemantics(
                child: Text(
                  'Détails',
                  style: textStyle?.copyWith(
                    color: NubiaColors.brand700,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Feuille de détail d'un consentement (issue #6478) : le lien « Détails »
/// de chaque carte était un stub snackbar « bientôt disponible », sans
/// contenu. N'affiche que des données réellement connues du front — la
/// durée de conservation et l'historique des changements ne sont exposés
/// par aucune API patient aujourd'hui (seul `GET /v1/cabinet/audit-log`,
/// côté pro, existe — voir [_RightsSection]) : renvoyés vers le contact DPO
/// plutôt qu'inventés.
class _ConsentDetailsSheet extends StatelessWidget {
  const _ConsentDetailsSheet({
    required this.consent,
    required this.legalBasis,
    this.recipientName,
  });

  final Consent consent;
  final String legalBasis;
  final String? recipientName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<NubiaTokens>()!;
    final status = _consentStatus(consent);
    final label = _kConsentLabels[consent.purpose] ?? _kUnknownConsentLabel;
    final description =
        _kConsentDescriptions[consent.purpose] ?? _kUnknownConsentLabel;

    return SingleChildScrollView(
      key: Key('consent_details_sheet_${consent.purpose}'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.titleMedium),
          const SizedBox(height: 16),
          _ConsentDetailRow(label: 'Finalité', value: description),
          _ConsentDetailRow(label: 'Base légale', value: legalBasis),
          _ConsentDetailRow(label: 'Statut', value: status.label),
          if (recipientName case final recipient?)
            _ConsentDetailRow(label: 'Destinataire', value: recipient),
          const SizedBox(height: 8),
          Text.rich(
            TextSpan(
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: tokens.textTertiary),
              children: [
                const TextSpan(
                  text: 'Durée de conservation et historique détaillé des '
                      'changements : sur demande auprès de notre délégué à '
                      'la protection des données, ',
                ),
                TextSpan(
                  text: _kDpoEmail,
                  style:
                      const TextStyle(decoration: TextDecoration.underline),
                  recognizer: TapGestureRecognizer()
                    ..onTap = () => sendEmail(_kDpoEmail),
                ),
                const TextSpan(text: '.'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Ligne libellé/valeur de [_ConsentDetailsSheet].
class _ConsentDetailRow extends StatelessWidget {
  const _ConsentDetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<NubiaTokens>()!;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: tokens.textTertiary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(value, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}

/// Chip `.wc` « pharmacie destinataire » sur la carte `partage_pharmacie`
/// (maquette design-v2, `patient-consentements.png`, #5209) : identifie
/// concrètement à qui les ordonnances sont transmises. Donnée = pharmacie
/// déclarée du patient (`GET /v1/account/pharmacy`, [ConsentsLoaded.pharmacyName]).
/// N'affiche rien tant qu'aucune pharmacie n'est déclarée — jamais de nom
/// inventé ni de chip placeholder vide.
class _PharmacyRecipientChip extends StatelessWidget {
  const _PharmacyRecipientChip({required this.pharmacyName});

  final String? pharmacyName;

  @override
  Widget build(BuildContext context) {
    final name = pharmacyName;
    if (name == null || name.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Align(
        alignment: Alignment.centerLeft,
        child: NubiaChip(
          key: const Key('consent_pharmacy_chip'),
          label: name,
          icon: Icons.store,
          variant: NubiaChipVariant.choice,
          selected: true,
          selectedBackground: NubiaColors.n50,
          selectedBorder: NubiaColors.n200,
        ),
      ),
    );
  }
}

/// Mentions RGPD obligatoires (responsable de traitement, hébergement HDS,
/// contact DPO) — maquette `.foot2` (issue #5214). Formulation verbatim de
/// la maquette : ne pas reformuler / retirer une fois en place.
class _ConsentsFooter extends StatelessWidget {
  const _ConsentsFooter();

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NubiaTokens>();
    final textStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
          color: tokens?.textTertiary,
        );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: NubiaCard(
        key: const Key('consents_footer'),
        backgroundColor: Theme.of(context).colorScheme.surface,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.gavel, size: 18, color: tokens?.textTertiary),
            const SizedBox(width: 12),
            Expanded(
              child: RichText(
                key: const Key('consents_footer_text'),
                text: TextSpan(
                  style: textStyle,
                  children: [
                    const TextSpan(
                      text:
                          'Responsable de traitement : $_kDataControllerName. '
                          'Données hébergées en France chez un hébergeur '
                          'agréé HDS. Délégué à la protection des '
                          'données : ',
                    ),
                    TextSpan(
                      text: _kDpoEmail,
                      style: textStyle?.copyWith(
                        decoration: TextDecoration.underline,
                      ),
                      recognizer: TapGestureRecognizer()
                        ..onTap = () => sendEmail(_kDpoEmail),
                    ),
                    const TextSpan(text: '.'),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Section « Vos droits » (maquette design-v2, #5213) : trois droits RGPD
/// opposables (export, historique, suppression) absents des bascules de
/// consentement au-dessus. Les 3 destinations n'existent pas encore côté
/// front (écrans hors périmètre de ce ticket) : le tap affiche un message
/// explicite plutôt qu'un no-op silencieux.
class _RightsSection extends StatelessWidget {
  const _RightsSection();

  void _showComingSoon(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final chevron = Icon(Icons.chevron_right, color: cs.onSurfaceVariant);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Vos droits',
            style: textTheme.titleSmall?.copyWith(
              color: cs.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          NubiaCard(
            key: const Key('consents_rights_card'),
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                ListRow(
                  key: const Key('right_export_data'),
                  leading: const Icon(Icons.download),
                  title: 'Exporter mes données',
                  subtitle: 'Copie complète, format lisible · sous 30 jours',
                  trailing: chevron,
                  onTap: () => _showComingSoon(
                    context,
                    'Export des données bientôt disponible.',
                  ),
                ),
                ListRow(
                  key: const Key('right_choices_history'),
                  leading: const Icon(Icons.history),
                  title: 'Historique de mes choix',
                  // Compteur = nb d'entrées d'audit
                  // (`0008_audit_consent.sql`, action='update_consent').
                  // Seul `GET /v1/cabinet/audit-log` (côté pro) existe
                  // aujourd'hui : aucune API front patient ne l'expose,
                  // donc masqué plutôt qu'une valeur inventée.
                  trailing: chevron,
                  onTap: () => _showComingSoon(
                    context,
                    'Historique des choix bientôt disponible.',
                  ),
                ),
                ListRow(
                  key: const Key('right_delete_account'),
                  leading: const Icon(Icons.person_off),
                  title: 'Supprimer mon compte',
                  subtitle: 'Sous réserve des durées légales de conservation',
                  showDivider: false,
                  trailing: chevron,
                  onTap: () => _showComingSoon(
                    context,
                    'Suppression de compte bientôt disponible.',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Feuille de confirmation du retrait du partage pharmacie (maquette
/// design-v2 `patient-consentements.png`, écran 2, #5211) : sépare ce qui
/// change de ce qui ne change pas avant que le retrait ne soit confirmé —
/// le geste ne doit plus être immédiat et silencieux. Porte aussi l'encart
/// conditionnel « commande en cours » (#5212).
class _PharmacyWithdrawalSheet extends StatefulWidget {
  const _PharmacyWithdrawalSheet();

  @override
  State<_PharmacyWithdrawalSheet> createState() =>
      _PharmacyWithdrawalSheetState();
}

class _PharmacyWithdrawalSheetState extends State<_PharmacyWithdrawalSheet> {
  late final Future<String?> _pendingOrderRef =
      context.read<ConsentsCubit>().pendingPharmacyOrderRef();
  bool _submitting = false;

  Future<void> _confirm() async {
    setState(() => _submitting = true);
    final cubit = context.read<ConsentsCubit>();
    await cubit.toggle(_kPharmacySharingPurpose, false);
    if (!mounted) return;
    final state = cubit.state;
    // Échec (hors ligne, etc.) : le SnackBar `toggleError` de la page
    // s'affiche déjà via son propre listener (#5215) — ici on ne fait que
    // garder la feuille ouverte et redonner la main, plutôt que la fermer
    // comme si le retrait avait réussi (#6488).
    if (state is ConsentsLoaded && state.toggleError != null) {
      setState(() => _submitting = false);
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<NubiaTokens>()!;
    // Contenu potentiellement plus haut que l'écran (encart commande en
    // cours + les deux blocs d'impact) : scrollable pour ne jamais déborder
    // (même motif que `_BookingPanel`, `appointments_page.dart`, #5337).
    return SingleChildScrollView(
      key: const Key('pharmacy_withdrawal_sheet'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Retirer le partage avec votre pharmacie ?',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Ce choix prend effet immédiatement et reste modifiable.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          FutureBuilder<String?>(
            key: const Key('pharmacy_withdrawal_pending_order'),
            future: _pendingOrderRef,
            builder: (context, snapshot) {
              final orderRef = snapshot.data;
              if (orderRef == null) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: _PendingOrderBanner(orderRef: orderRef),
              );
            },
          ),
          _ConsentImpactSection(
            key: const Key('pharmacy_withdrawal_changes'),
            title: 'Ce qui change',
            icon: Icons.cancel,
            iconColor: tokens.dangerFg,
            // Nom de la pharmacie non exposé côté front patient (même limite
            // que `_kDataControllerName` ci-dessus, #5214) : formulation
            // générique plutôt qu'un nom inventé.
            items: const [
              'Vos prochaines ordonnances ne seront plus transmises à '
                  'votre pharmacie.',
              'Vous devrez présenter votre ordonnance papier ou le PDF de '
                  'votre application.',
            ],
          ),
          const SizedBox(height: 16),
          _ConsentImpactSection(
            key: const Key('pharmacy_withdrawal_unchanged'),
            title: 'Ce qui ne change pas',
            icon: Icons.check_circle,
            iconColor: tokens.successFg,
            items: const [
              'Vos ordonnances passées restent dans vos documents.',
              'Vos rendez-vous et votre suivi de soins sont inchangés.',
            ],
          ),
          const SizedBox(height: 24),
          NubiaButton(
            key: const Key('pharmacy_withdrawal_confirm_button'),
            label: 'Retirer ce consentement',
            icon: Icons.block,
            variant: NubiaButtonVariant.destructive,
            isLoading: _submitting,
            onPressed: _submitting ? null : _confirm,
          ),
          const SizedBox(height: 8),
          NubiaButton(
            key: const Key('pharmacy_withdrawal_cancel_button'),
            label: 'Annuler',
            variant: NubiaButtonVariant.secondary,
            onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}

/// Bloc « Ce qui change » / « Ce qui ne change pas » de la feuille de
/// retrait (maquette design-v2, #5211) : sépare les conséquences concrètes
/// du retrait de ce qui reste inchangé, pour que le geste ne soit plus
/// silencieux.
class _ConsentImpactSection extends StatelessWidget {
  const _ConsentImpactSection({
    super.key,
    required this.title,
    required this.icon,
    required this.iconColor,
    required this.items,
  });

  final String title;
  final IconData icon;
  final Color iconColor;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        for (final item in items) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 20, color: iconColor),
              const SizedBox(width: 8),
              Expanded(child: Text(item, style: textTheme.bodyMedium)),
            ],
          ),
          if (item != items.last) const SizedBox(height: 8),
        ],
      ],
    );
  }
}

/// Encart `.warnb` « commande en cours » (verbatim maquette design-v2) :
/// signale que le retrait ne s'applique qu'aux ordonnances futures, la
/// commande déjà transmise étant honorée normalement. [orderRef] vient
/// toujours de la donnée — jamais codé en dur (critère d'acceptation #5212).
class _PendingOrderBanner extends StatelessWidget {
  const _PendingOrderBanner({required this.orderRef});

  final String orderRef;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NubiaTokens>();
    final textTheme = Theme.of(context).textTheme;
    final textStyle = textTheme.bodySmall?.copyWith(color: tokens?.warningFg);

    return Container(
      key: const Key('pharmacy_pending_order_banner'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tokens?.warningBg,
        border: Border.all(color: NubiaColors.warningBorder),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info, size: 18, color: tokens?.warningFg),
          const SizedBox(width: 10),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: textStyle,
                children: [
                  const TextSpan(
                    text: 'Une commande est en cours. ',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  TextSpan(
                    text: 'La commande $orderRef, déjà transmise, sera '
                        'honorée normalement — le retrait ne s\'applique '
                        "qu'aux ordonnances futures.",
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

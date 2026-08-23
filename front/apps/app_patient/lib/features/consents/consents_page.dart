import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

import 'consents_cubit.dart';

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

/// Seule finalité dont le retrait passe par une feuille de confirmation
/// (maquette design-v2, #5211/#5212) : les autres bascules restent
/// immédiates, comme avant.
const _kPharmacySharingPurpose = 'partage_pharmacie';

/// Bascule un consentement — sauf le retrait du partage pharmacie, qui
/// passe d'abord par une feuille de confirmation (#5211) signalant le cas
/// particulier d'une commande déjà transmise (#5212).
void _handleToggle(BuildContext context, String purpose, bool granted) {
  if (purpose == _kPharmacySharingPurpose && !granted) {
    final cubit = context.read<ConsentsCubit>();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => BlocProvider.value(
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
        appBar: AppBar(title: const Text('Consentements')),
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
          s is ConsentsError ||
          (s is ConsentsLoaded && s.toggleError != null),
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
          return ListView(
            key: const Key('consents_list'),
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Vous pouvez retirer un consentement à tout moment (RGPD). '
                  'Le retrait prend effet immédiatement.',
                ),
              ),
              for (final consent in state.consents)
                SwitchListTile(
                  key: Key('consent_${consent.purpose}'),
                  title: Text(
                    _kConsentLabels[consent.purpose] ?? _kUnknownConsentLabel,
                  ),
                  value: consent.granted,
                  onChanged: state.pending == consent.purpose
                      ? null
                      : (v) => _handleToggle(context, consent.purpose, v),
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
                      text: 'Responsable de traitement : $_kDataControllerName. '
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
/// design-v2 `patient-consentements.png`, écran 2).
///
/// Ce widget ne couvre que le périmètre de #5212 : l'encart conditionnel
/// « commande en cours ». Les blocs « ce qui change » / « ce qui ne change
/// pas » de la maquette relèvent de #5211 (feuille de confirmation de
/// retrait) et restent à ajouter par ce ticket.
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
    await context
        .read<ConsentsCubit>()
        .toggle(_kPharmacySharingPurpose, false);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
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
          NubiaButton(
            key: const Key('pharmacy_withdrawal_confirm_button'),
            label: 'Retirer ce consentement',
            variant: NubiaButtonVariant.destructive,
            isLoading: _submitting,
            onPressed: _submitting ? null : _confirm,
          ),
          const SizedBox(height: 8),
          NubiaButton(
            key: const Key('pharmacy_withdrawal_cancel_button'),
            label: 'Annuler',
            variant: NubiaButtonVariant.secondary,
            onPressed:
                _submitting ? null : () => Navigator.of(context).pop(),
          ),
        ],
      ),
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

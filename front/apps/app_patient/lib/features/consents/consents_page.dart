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
                      : (v) => context
                          .read<ConsentsCubit>()
                          .toggle(consent.purpose, v),
                ),
              const _ConsentsFooter(),
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

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

import 'notification_prefs_cubit.dart';

class NotificationPrefsPage extends StatelessWidget {
  const NotificationPrefsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => GetIt.instance<NotificationPrefsCubit>()..load(),
      child: Scaffold(
        appBar: AppBar(title: const Text('Préférences notifications')),
        body: const _PrefsBody(),
      ),
    );
  }
}

class _PrefsBody extends StatelessWidget {
  const _PrefsBody();

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<NotificationPrefsCubit, NotificationPrefsState>(
      listenWhen: (_, s) => s is NotificationPrefsError,
      listener: (context, state) {
        if (state is NotificationPrefsError) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(state.message)),
          );
        }
      },
      builder: (context, state) {
        if (state is NotificationPrefsLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        if (state is NotificationPrefsError) {
          return NubiaErrorWidget(
            message: state.message,
            onRetry: () => context.read<NotificationPrefsCubit>().load(),
          );
        }
        if (state is NotificationPrefsLoaded) {
          final p = state.prefs;
          final cubit = context.read<NotificationPrefsCubit>();
          final locked = state.saving;
          return ListView(
            key: const Key('notif_prefs_list'),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              _sectionLabel(context, 'Canaux'),
              _switch('notif_push', 'Notifications push', p.pushEnabled, locked,
                  (v) => cubit.save(p.copyWith(pushEnabled: v))),
              _switch('notif_email', 'E-mail', p.emailEnabled, locked,
                  (v) => cubit.save(p.copyWith(emailEnabled: v))),
              _switch('notif_sms', 'SMS', p.smsEnabled, locked,
                  (v) => cubit.save(p.copyWith(smsEnabled: v))),
              const Divider(),
              const SizedBox(height: 8),
              NubiaCard(
                key: const Key('notif_block_quiet_hours'),
                child: _PrefRow(
                  rowKey: const Key('notif_quiet_hours'),
                  icon: Icons.bedtime,
                  title: 'Pas avant 8h ni après 21h',
                  subtitle: 'Sauf urgence de votre cabinet',
                  value: p.quietHours,
                  locked: locked,
                  onChanged: (v) => cubit.save(p.copyWith(quietHours: v)),
                ),
              ),
              const SizedBox(height: 16),
              _NotifBlock(
                blockKey: const Key('notif_block_appointments'),
                icon: Icons.event,
                title: 'Rendez-vous',
                rows: [
                  _LockedPrefRow(
                    rowKey: const Key('notif_appointments'),
                    title: 'Confirmation et modification',
                    subtitle: "Quand un RDV est créé, déplacé ou annulé",
                  ),
                  _PendingApiPrefRow(
                    rowKey: const Key('notif_appointments_reminder_48h'),
                    title: 'Rappel 48 h avant',
                  ),
                  _PendingApiPrefRow(
                    rowKey: const Key('notif_appointments_reminder_2h'),
                    title: 'Rappel 2 h avant',
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _NotifBlock(
                blockKey: const Key('notif_block_care'),
                icon: Icons.medical_services,
                title: 'Mes soins',
                rows: [
                  _PrefRow(
                    rowKey: const Key('notif_messages'),
                    title: 'Messages du cabinet',
                    subtitle: 'Réponses de votre praticien ou du secrétariat',
                    value: p.messages,
                    locked: locked,
                    onChanged: (v) => cubit.save(p.copyWith(messages: v)),
                  ),
                  _PrefRow(
                    rowKey: const Key('notif_documents'),
                    title: 'Nouveaux documents',
                    subtitle: 'Ordonnances, comptes-rendus, factures',
                    value: p.documents,
                    locked: locked,
                    onChanged: (v) => cubit.save(p.copyWith(documents: v)),
                  ),
                  _PendingApiPrefRow(
                    rowKey: const Key('notif_pharmacy_order'),
                    title: 'Suivi de commande pharmacie',
                    subtitle: 'Préparation, commande prête à retirer',
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _NotifBlock(
                blockKey: const Key('notif_block_billing'),
                icon: Icons.payments,
                title: 'Devis et paiements',
                rows: [
                  _PendingApiPrefRow(
                    rowKey: const Key('notif_quote'),
                    title: 'Nouveau devis à signer',
                  ),
                  _PrefRow(
                    rowKey: const Key('notif_payments'),
                    title: 'Rappel de paiement',
                    subtitle: 'Solde impayé au cabinet',
                    value: p.payments,
                    locked: locked,
                    onChanged: (v) => cubit.save(p.copyWith(payments: v)),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _NotifBlock(
                blockKey: const Key('notif_block_practice'),
                icon: Icons.campaign,
                title: 'Le cabinet',
                rows: [
                  _PrefRow(
                    rowKey: const Key('notif_prevention'),
                    title: 'Actualités et prévention',
                    subtitle: 'Dépend de votre consentement marketing',
                    value: p.prevention,
                    locked: locked,
                    onChanged: (v) => cubit.save(p.copyWith(prevention: v)),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _infoBanner(context),
            ],
          );
        }
        return const SizedBox.shrink();
      },
    );
  }

  Widget _sectionLabel(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(
          text,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      );

  Widget _switch(String key, String title, bool value, bool locked,
          ValueChanged<bool> onChanged) =>
      SwitchListTile(
        key: Key(key),
        title: Text(title),
        value: value,
        onChanged: locked ? null : onChanged,
      );

  Widget _infoBanner(BuildContext context) {
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    return Container(
      key: const Key('notif_prefs_info_banner'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tokens.infoBg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.shield_outlined, size: 18, color: tokens.infoFg),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              "Les notifications de rendez-vous ne peuvent pas être "
              "désactivées : elles vous informent d'un changement qui "
              "vous concerne directement. Vous pouvez en revanche "
              'choisir par quel canal les recevoir.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: tokens.infoFg,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------

/// Bloc carte thématique (`.blk`) : en-tête icône + titre (`.bh`), puis les
/// lignes bascule (`.tgr`) séparées par des diviseurs.
class _NotifBlock extends StatelessWidget {
  const _NotifBlock({
    required this.blockKey,
    required this.icon,
    required this.title,
    required this.rows,
  });

  final Key blockKey;
  final IconData icon;
  final String title;
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return NubiaCard(
      key: blockKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: cs.primary),
              const SizedBox(width: 8),
              Text(
                title,
                style: textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (final (i, row) in rows.indexed) ...[
            if (i > 0) const Divider(height: 20),
            row,
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------

/// Ligne bascule (`.tgr`) : titre (`.l1`) + sous-titre (`.l2`) + [NubiaToggle].
class _PrefRow extends StatelessWidget {
  const _PrefRow({
    required this.rowKey,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.locked,
    required this.onChanged,
    this.icon,
  });

  final Key rowKey;
  final IconData? icon;
  final String title;
  final String subtitle;
  final bool value;
  final bool locked;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 20, color: cs.primary),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: textTheme.bodyLarge),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        NubiaToggle(
          key: rowKey,
          value: value,
          onChanged: locked ? null : onChanged,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

/// Bascule verrouillée activée : les notifications de RDV ne peuvent pas
/// être désactivées (seul le canal de réception reste choisissable).
class _LockedPrefRow extends StatelessWidget {
  const _LockedPrefRow({
    required this.rowKey,
    required this.title,
    required this.subtitle,
  });

  final Key rowKey;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(child: Text(title, style: textTheme.bodyLarge)),
                  const SizedBox(width: 8),
                  const _PrefBadge(
                    badgeKey: Key('notif_appointments_locked_badge'),
                    icon: Icons.lock,
                    label: 'Toujours activé',
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        NubiaToggle(key: rowKey, value: true, onChanged: null),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

/// Sous-bascule sans champ `NotificationPreferences` dédié : le mockup
/// introduit une granularité que l'API n'expose pas encore (cf. #5314).
/// Désactivée plutôt que mappée à un champ parent, pour ne jamais persister
/// un état que l'utilisateur n'a pas explicitement choisi.
class _PendingApiPrefRow extends StatelessWidget {
  const _PendingApiPrefRow({
    required this.rowKey,
    required this.title,
    this.subtitle,
  });

  final Key rowKey;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    final textTheme = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      title,
                      style: textTheme.bodyLarge
                          ?.copyWith(color: tokens.textTertiary),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const _PrefBadge(
                    icon: Icons.hourglass_empty,
                    label: 'Bientôt disponible',
                  ),
                ],
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  style:
                      textTheme.bodySmall?.copyWith(color: tokens.textTertiary),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 12),
        NubiaToggle(key: rowKey, value: false, onChanged: null),
      ],
    );
  }
}

/// Étiquette compacte (icône + libellé) utilisée pour signaler l'état d'une
/// bascule : verrouillée (`Toujours activé`) ou en attente d'API
/// (`Bientôt disponible`).
class _PrefBadge extends StatelessWidget {
  const _PrefBadge({this.badgeKey, required this.icon, required this.label});

  final Key? badgeKey;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    return Container(
      key: badgeKey,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: tokens.borderSubtle,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: tokens.textTertiary),
          const SizedBox(width: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: tokens.textTertiary,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }
}

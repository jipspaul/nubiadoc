import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

import 'notification_prefs_cubit.dart';

/// Écran « Préférences de notifications » pro, accessible depuis le ⚙ de la
/// barre latérale (#6341). Un switch in-app + un switch push par catégorie
/// pertinente pour le rôle secrétariat, et un switch e-mail en plus pour les
/// catégories qui le supportent côté API (rdv/messagerie/devis).
class NotificationPrefsPage extends StatelessWidget {
  const NotificationPrefsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => GetIt.instance<NotificationPrefsCubit>()..load(),
      child: Scaffold(
        appBar: AppBar(title: const Text('Préférences de notifications')),
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
              _CategoryCard(
                cardKey: const Key('notif_block_rdv'),
                icon: Icons.event_outlined,
                title: 'Rendez-vous',
                inAppSubtitle: 'Demandes de rendez-vous et de rappel',
                inAppKey: const Key('notif_inapp_rdv'),
                inAppValue: p.inappRdv,
                onInAppChanged:
                    locked ? null : (v) => cubit.save(p.copyWith(inappRdv: v)),
                emailKey: const Key('notif_email_rdv'),
                emailValue: p.emailRdv,
                onEmailChanged:
                    locked ? null : (v) => cubit.save(p.copyWith(emailRdv: v)),
                pushKey: const Key('notif_push_rdv'),
                pushValue: p.pushRdv,
                onPushChanged:
                    locked ? null : (v) => cubit.save(p.copyWith(pushRdv: v)),
              ),
              const SizedBox(height: 16),
              _CategoryCard(
                cardKey: const Key('notif_block_messagerie'),
                icon: Icons.forum_outlined,
                title: 'Messagerie',
                inAppSubtitle: 'Nouveaux messages du patient ou du cabinet',
                inAppKey: const Key('notif_inapp_messagerie'),
                inAppValue: p.inappMessagerie,
                onInAppChanged: locked
                    ? null
                    : (v) => cubit.save(p.copyWith(inappMessagerie: v)),
                emailKey: const Key('notif_email_messagerie'),
                emailValue: p.emailMessagerie,
                onEmailChanged: locked
                    ? null
                    : (v) => cubit.save(p.copyWith(emailMessagerie: v)),
                pushKey: const Key('notif_push_messagerie'),
                pushValue: p.pushMessagerie,
                onPushChanged: locked
                    ? null
                    : (v) => cubit.save(p.copyWith(pushMessagerie: v)),
              ),
              const SizedBox(height: 16),
              _CategoryCard(
                cardKey: const Key('notif_block_devis'),
                icon: Icons.request_quote_outlined,
                title: 'Devis',
                inAppSubtitle: 'Devis envoyés, acceptés ou refusés',
                inAppKey: const Key('notif_inapp_devis'),
                inAppValue: p.inappDevis,
                onInAppChanged:
                    locked ? null : (v) => cubit.save(p.copyWith(inappDevis: v)),
                emailKey: const Key('notif_email_devis'),
                emailValue: p.emailDevis,
                onEmailChanged:
                    locked ? null : (v) => cubit.save(p.copyWith(emailDevis: v)),
                pushKey: const Key('notif_push_devis'),
                pushValue: p.pushDevis,
                onPushChanged:
                    locked ? null : (v) => cubit.save(p.copyWith(pushDevis: v)),
              ),
              const SizedBox(height: 16),
              _CategoryCard(
                cardKey: const Key('notif_block_stock'),
                icon: Icons.inventory_2_outlined,
                title: 'Demandes de stock',
                inAppSubtitle: 'Ruptures et demandes de réapprovisionnement',
                inAppKey: const Key('notif_inapp_stock'),
                inAppValue: p.inappStock,
                onInAppChanged:
                    locked ? null : (v) => cubit.save(p.copyWith(inappStock: v)),
                pushKey: const Key('notif_push_stock'),
                pushValue: p.pushStock,
                onPushChanged:
                    locked ? null : (v) => cubit.save(p.copyWith(pushStock: v)),
              ),
            ],
          );
        }
        return const SizedBox.shrink();
      },
    );
  }
}

/// Bloc carte : une catégorie de notification, un switch in-app et, si
/// [emailKey]/[pushKey] sont fournis, un switch email et/ou push en plus
/// (mêmes catégories que l'API expose le canal correspondant).
class _CategoryCard extends StatelessWidget {
  const _CategoryCard({
    required this.cardKey,
    required this.icon,
    required this.title,
    required this.inAppSubtitle,
    required this.inAppKey,
    required this.inAppValue,
    required this.onInAppChanged,
    this.emailKey,
    this.emailValue,
    this.onEmailChanged,
    this.pushKey,
    this.pushValue,
    this.onPushChanged,
  });

  final Key cardKey;
  final IconData icon;
  final String title;
  final String inAppSubtitle;
  final Key inAppKey;
  final bool inAppValue;
  final ValueChanged<bool>? onInAppChanged;
  final Key? emailKey;
  final bool? emailValue;
  final ValueChanged<bool>? onEmailChanged;
  final Key? pushKey;
  final bool? pushValue;
  final ValueChanged<bool>? onPushChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return NubiaCard(
      key: cardKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: cs.primary),
              const SizedBox(width: 8),
              Text(
                title,
                style:
                    textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _PrefRow(
            rowKey: inAppKey,
            categoryTitle: title,
            title: 'Dans l\'application',
            subtitle: inAppSubtitle,
            value: inAppValue,
            onChanged: onInAppChanged,
          ),
          if (emailKey != null) ...[
            const Divider(height: 20),
            _PrefRow(
              rowKey: emailKey!,
              categoryTitle: title,
              title: 'Par e-mail',
              subtitle: 'En plus de la notification dans l\'application',
              value: emailValue ?? false,
              onChanged: onEmailChanged,
            ),
          ],
          if (pushKey != null) ...[
            const Divider(height: 20),
            _PrefRow(
              rowKey: pushKey!,
              categoryTitle: title,
              title: 'Sur mobile (push)',
              subtitle: 'Notification push sur le téléphone',
              value: pushValue ?? false,
              onChanged: onPushChanged,
            ),
          ],
        ],
      ),
    );
  }
}

class _PrefRow extends StatelessWidget {
  const _PrefRow({
    required this.rowKey,
    required this.categoryTitle,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final Key rowKey;
  final String categoryTitle;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: textTheme.bodyLarge),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style:
                    textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Semantics(
          container: true,
          label: '$categoryTitle — $title',
          child: NubiaToggle(key: rowKey, value: value, onChanged: onChanged),
        ),
      ],
    );
  }
}

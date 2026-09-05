import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

import 'notification_prefs_cubit.dart';

/// Écran « Préférences de notifications » pro, accessible depuis le ⚙ de la
/// page d'accueil (#6341). Seule catégorie pertinente pour le rôle
/// infirmière : les offres de visite (`inapp_visites`/`push_visites`), pas
/// de canal e-mail côté API pour cette catégorie.
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
                cardKey: const Key('notif_block_visites'),
                icon: Icons.directions_walk_outlined,
                title: 'Visites',
                inAppSubtitle: 'Nouvelles offres de visite à domicile',
                inAppKey: const Key('notif_inapp_visites'),
                inAppValue: p.inappVisites,
                onInAppChanged: locked
                    ? null
                    : (v) => cubit.save(p.copyWith(inappVisites: v)),
                pushKey: const Key('notif_push_visites'),
                pushValue: p.pushVisites,
                onPushChanged: locked
                    ? null
                    : (v) => cubit.save(p.copyWith(pushVisites: v)),
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
/// [pushKey] est fourni, un switch push en plus (pas de canal e-mail
/// côté API pour les catégories réservées à cette app).
class _CategoryCard extends StatelessWidget {
  const _CategoryCard({
    required this.cardKey,
    required this.icon,
    required this.title,
    required this.inAppSubtitle,
    required this.inAppKey,
    required this.inAppValue,
    required this.onInAppChanged,
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

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

import 'pharma_notification_prefs_cubit.dart';

/// Écran « Préférences de notifications » pro, accessible depuis le ⚙ du
/// panneau cloche (#6265). Un switch in-app par catégorie pertinente pour le
/// rôle pharmacie + un switch email pour les catégories qui le supportent.
class PharmaNotificationPrefsPage extends StatelessWidget {
  const PharmaNotificationPrefsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) =>
          GetIt.instance<PharmaNotificationPrefsCubit>()..load(),
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
    return BlocConsumer<PharmaNotificationPrefsCubit,
        PharmaNotificationPrefsState>(
      listenWhen: (_, s) => s is PharmaNotificationPrefsError,
      listener: (context, state) {
        if (state is PharmaNotificationPrefsError) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(state.message)),
          );
        }
      },
      builder: (context, state) {
        if (state is PharmaNotificationPrefsLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        if (state is PharmaNotificationPrefsError) {
          return NubiaErrorWidget(
            message: state.message,
            onRetry: () =>
                context.read<PharmaNotificationPrefsCubit>().load(),
          );
        }
        if (state is PharmaNotificationPrefsLoaded) {
          final p = state.prefs;
          final cubit = context.read<PharmaNotificationPrefsCubit>();
          final locked = state.saving;
          return ListView(
            key: const Key('pharma_notif_prefs_list'),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              _CategoryCard(
                cardKey: const Key('pharma_notif_block_messagerie'),
                icon: Icons.forum_outlined,
                title: 'Messagerie',
                inAppKey: const Key('pharma_notif_inapp_messagerie'),
                inAppSubtitle: 'Nouveaux messages du patient ou du cabinet',
                inAppValue: p.inappMessagerie,
                onInAppChanged: locked
                    ? null
                    : (v) => cubit.save(p.copyWith(inappMessagerie: v)),
                emailKey: const Key('pharma_notif_email_messagerie'),
                emailValue: p.emailMessagerie,
                onEmailChanged: locked
                    ? null
                    : (v) => cubit.save(p.copyWith(emailMessagerie: v)),
              ),
              const SizedBox(height: 16),
              _CategoryCard(
                cardKey: const Key('pharma_notif_block_devis'),
                icon: Icons.request_quote_outlined,
                title: 'Devis',
                inAppSubtitle: 'Devis envoyés, acceptés ou refusés',
                inAppKey: const Key('pharma_notif_inapp_devis'),
                inAppValue: p.inappDevis,
                onInAppChanged:
                    locked ? null : (v) => cubit.save(p.copyWith(inappDevis: v)),
                emailKey: const Key('pharma_notif_email_devis'),
                emailValue: p.emailDevis,
                onEmailChanged:
                    locked ? null : (v) => cubit.save(p.copyWith(emailDevis: v)),
              ),
              const SizedBox(height: 16),
              _CategoryCard(
                cardKey: const Key('pharma_notif_block_stock'),
                icon: Icons.inventory_2_outlined,
                title: 'Demandes de stock',
                inAppSubtitle: 'Ruptures et demandes de réapprovisionnement',
                inAppKey: const Key('pharma_notif_inapp_stock'),
                inAppValue: p.inappStock,
                onInAppChanged:
                    locked ? null : (v) => cubit.save(p.copyWith(inappStock: v)),
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
/// [emailKey] est fourni, un switch email en plus (mêmes catégories que
/// l'API expose un canal email, cf. #6257).
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
            title: 'Dans l\'application',
            subtitle: inAppSubtitle,
            value: inAppValue,
            onChanged: onInAppChanged,
          ),
          if (emailKey != null) ...[
            const Divider(height: 20),
            _PrefRow(
              rowKey: emailKey!,
              title: 'Par e-mail',
              subtitle: 'En plus de la notification dans l\'application',
              value: emailValue ?? false,
              onChanged: onEmailChanged,
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
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final Key rowKey;
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
        NubiaToggle(key: rowKey, value: value, onChanged: onChanged),
      ],
    );
  }
}

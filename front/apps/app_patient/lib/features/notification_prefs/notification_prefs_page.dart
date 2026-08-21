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
            children: [
              _sectionLabel(context, 'Canaux'),
              _switch('notif_push', 'Notifications push', p.pushEnabled, locked,
                  (v) => cubit.save(p.copyWith(pushEnabled: v))),
              _switch('notif_email', 'E-mail', p.emailEnabled, locked,
                  (v) => cubit.save(p.copyWith(emailEnabled: v))),
              _switch('notif_sms', 'SMS', p.smsEnabled, locked,
                  (v) => cubit.save(p.copyWith(smsEnabled: v))),
              const Divider(),
              _sectionLabel(context, 'Rendez-vous'),
              _lockedSwitch(
                'notif_appointments',
                'Confirmation et modification',
                "Quand un RDV est créé, déplacé ou annulé",
              ),
              const Divider(),
              _sectionLabel(context, "Autres événements"),
              _switch('notif_documents', 'Documents', p.documents, locked,
                  (v) => cubit.save(p.copyWith(documents: v))),
              _switch('notif_messages', 'Messages', p.messages, locked,
                  (v) => cubit.save(p.copyWith(messages: v))),
              _switch('notif_payments', 'Paiements', p.payments, locked,
                  (v) => cubit.save(p.copyWith(payments: v))),
              _switch('notif_prevention', 'Prévention & rappels', p.prevention,
                  locked, (v) => cubit.save(p.copyWith(prevention: v))),
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

  /// Bascule verrouillée activée : les notifications de RDV ne peuvent pas
  /// être désactivées (seul le canal de réception reste choisissable).
  Widget _lockedSwitch(String key, String title, String subtitle) =>
      Builder(
        builder: (context) => SwitchListTile(
          key: Key(key),
          title: Row(
            children: [
              Flexible(child: Text(title)),
              const SizedBox(width: 8),
              _lockedBadge(context),
            ],
          ),
          subtitle: Text(subtitle),
          value: true,
          onChanged: null,
        ),
      );

  Widget _lockedBadge(BuildContext context) {
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    return Container(
      key: const Key('notif_appointments_locked_badge'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: tokens.borderSubtle,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lock, size: 12, color: tokens.textTertiary),
          const SizedBox(width: 4),
          Text(
            'Toujours activé',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: tokens.textTertiary,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }

  Widget _infoBanner(BuildContext context) {
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Container(
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
      ),
    );
  }
}

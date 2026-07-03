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
              _sectionLabel(context, "Types d'événements"),
              _switch('notif_appointments', 'Rendez-vous', p.appointments,
                  locked, (v) => cubit.save(p.copyWith(appointments: v))),
              _switch('notif_documents', 'Documents', p.documents, locked,
                  (v) => cubit.save(p.copyWith(documents: v))),
              _switch('notif_messages', 'Messages', p.messages, locked,
                  (v) => cubit.save(p.copyWith(messages: v))),
              _switch('notif_payments', 'Paiements', p.payments, locked,
                  (v) => cubit.save(p.copyWith(payments: v))),
              _switch('notif_prevention', 'Prévention & rappels',
                  p.prevention, locked,
                  (v) => cubit.save(p.copyWith(prevention: v))),
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
}

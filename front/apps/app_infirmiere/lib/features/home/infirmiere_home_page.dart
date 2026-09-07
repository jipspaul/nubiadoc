import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

import '../../infirmiere_config.dart';
import '../../router/app_router.dart';
import '../../session/infirmiere_auth_cubit.dart';
import '../notifications/notifications_bloc.dart';
import '../notifications/notifications_event.dart';
import '../notifications/notifications_panel.dart';
import '../notifications/notifications_state.dart';
import '../nurse/home_care_acts.dart';
import '../nurse/nurse_cubit.dart';

/// Index de l'onglet Offres dans [_HomeScaffoldState._tab] — cible du
/// deep-link local depuis une notification (#6266).
const _offersTabIndex = 1;

/// Accueil infirmière : 3 onglets (Disponibilité, Offres, Ma visite).
class InfirmiereHomePage extends StatelessWidget {
  const InfirmiereHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<NurseCubit>(
          create: (_) => GetIt.instance<NurseCubit>()
            ..loadProfile()
            ..loadOffers()
            ..loadActiveVisit(),
        ),
        BlocProvider<NotificationsBloc>(
          create: (_) => GetIt.instance<NotificationsBloc>()
            ..add(const NotificationsLoadRequested()),
        ),
      ],
      child: const _HomeScaffold(),
    );
  }
}

class _HomeScaffold extends StatefulWidget {
  const _HomeScaffold();

  @override
  State<_HomeScaffold> createState() => _HomeScaffoldState();
}

class _HomeScaffoldState extends State<_HomeScaffold> {
  int _tab = 0;

  Future<void> _openNotifications(BuildContext context) async {
    final notificationsBloc = context.read<NotificationsBloc>();
    final goToOffers = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => BlocProvider.value(
        value: notificationsBloc,
        child: NurseNotificationsPanel(
          onNotificationTap: () => Navigator.of(sheetContext).pop(true),
        ),
      ),
    );
    if (goToOffers == true && mounted) {
      setState(() => _tab = _offersTabIndex);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(InfirmiereConfig.appTitle),
        actions: [
          BlocSelector<NotificationsBloc, NotificationsState, bool>(
            selector: (s) => s is NotificationsLoaded && s.unreadCount > 0,
            builder: (context, hasUnread) => IconButton(
              key: const Key('header_action_notifications'),
              tooltip: 'Notifications',
              icon: Badge(
                key: const Key('header_notification_badge'),
                isLabelVisible: hasUnread,
                child: const Icon(Icons.notifications_outlined),
              ),
              onPressed: () => _openNotifications(context),
            ),
          ),
          IconButton(
            key: const Key('notification_prefs_button'),
            tooltip: 'Préférences de notifications',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () =>
                context.go(AppRouter.notificationPreferences),
          ),
          IconButton(
            tooltip: 'Se déconnecter',
            icon: const Icon(Icons.logout),
            onPressed: () => context.read<InfirmiereAuthCubit>().signOut(),
          ),
        ],
      ),
      body: BlocConsumer<NurseCubit, NurseState>(
        listener: (context, state) {
          if (state.error != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(state.error!)),
            );
          }
        },
        builder: (context, state) => IndexedStack(
          index: _tab,
          children: [
            _AvailabilityTab(state: state),
            _OffersTab(state: state),
            _VisitTab(state: state),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.toggle_on_outlined), label: 'Disponibilité'),
          NavigationDestination(
              icon: Icon(Icons.inbox_outlined), label: 'Offres'),
          NavigationDestination(
              icon: Icon(Icons.directions_walk_outlined), label: 'Ma visite'),
        ],
      ),
    );
  }
}

class _AvailabilityTab extends StatelessWidget {
  const _AvailabilityTab({required this.state});
  final NurseState state;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Disponibilité',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            state.online
                ? 'Vous êtes EN LIGNE — vous recevez les demandes de visite proches.'
                : 'Vous êtes hors ligne. Passez en ligne pour recevoir des demandes.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          SwitchListTile(
            key: const Key('availability_switch'),
            title: const Text('En ligne'),
            value: state.online,
            // TODO(nubia): pousser la position réelle (geolocator) au passage en ligne.
            onChanged: (v) => context.read<NurseCubit>().setOnline(v),
          ),
        ],
      ),
    );
  }
}

class _OffersTab extends StatelessWidget {
  const _OffersTab({required this.state});
  final NurseState state;

  @override
  Widget build(BuildContext context) {
    if (state.offers.isEmpty) {
      return RefreshIndicator(
        onRefresh: () => context.read<NurseCubit>().loadOffers(),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 120),
            NubiaEmptyState(
              icon: Icons.inbox_outlined,
              title: 'Aucune offre',
              subtitle: 'Les demandes de visite proches apparaîtront ici.',
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: () => context.read<NurseCubit>().loadOffers(),
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: state.offers.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, i) {
          final o = state.offers[i];
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(o.patientDisplayName,
                            style: Theme.of(context).textTheme.titleMedium),
                      ),
                      Text(
                        NubiaMoney.formatCents(o.estimatedPriceCents),
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(o.requestedActs.map(homeCareActLabel).join(' · ')),
                  Text('${o.address['city'] ?? ''} ${o.address['postal_code'] ?? ''}',
                      style: Theme.of(context).textTheme.bodySmall),
                  if (o.notes != null && o.notes!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      o.notes!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontStyle: FontStyle.italic,
                          ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: NubiaButton(
                          label: 'Accepter',
                          isLoading: state.loading,
                          onPressed: () =>
                              context.read<NurseCubit>().accept(o),
                        ),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: () =>
                            context.read<NurseCubit>().decline(o),
                        child: const Text('Passer'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _VisitTab extends StatelessWidget {
  const _VisitTab({required this.state});
  final NurseState state;

  @override
  Widget build(BuildContext context) {
    final v = state.activeVisit;
    if (v == null) {
      return const NubiaEmptyState(
        icon: Icons.directions_walk_outlined,
        title: 'Aucune visite en cours',
        subtitle: 'Acceptez une offre pour démarrer une visite.',
      );
    }
    final (label, action) = switch (v.status) {
      'accepted' => ('Je pars', 'en-route'),
      'en_route' => ('Je suis arrivé·e', 'arrived'),
      'arrived' => ('Visite terminée', 'done'),
      _ => (null as String?, null as String?),
    };
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(v.patientDisplayName,
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(v.requestedActs.map(homeCareActLabel).join(' · ')),
          Text('${v.address['line1'] ?? ''}, ${v.address['city'] ?? ''}'),
          const SizedBox(height: 8),
          Chip(label: Text('Statut : ${visitStatusLabel(v.status)}')),
          const Spacer(),
          if (label != null && action != null)
            NubiaButton(
              label: label,
              isLoading: state.loading,
              onPressed: () => context.read<NurseCubit>().transition(action),
            ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

import '../../router/app_router.dart';
import '../home/home_bloc.dart';
import '../home/home_event.dart';
import '../home/home_page.dart';
import '../messaging/messaging_bloc.dart';
import '../messaging/messaging_event.dart';
import '../notifications/notifications_bloc.dart';
import '../notifications/notifications_event.dart';
import '../notifications/notifications_state.dart';
import 'patient_bottom_nav.dart';

/// Patient home shell : onglet « Accueil » (tableau de bord, [HomePage]) de
/// la barre de 5 onglets du shell patient.
///
/// #8624 : les 4 autres onglets (Mes RDV / Messages / Documents / Profil)
/// sont chacun leur propre route de premier niveau (`AppRouter.mesRdv` etc.),
/// poussée via [goToPatientTab] — sélectionner un onglet pousse donc son URL
/// au lieu de ne muter qu'un état local, pour qu'un rechargement ou un retour
/// navigateur restent sur l'onglet affiché.
///
/// L'annuaire (recherche de praticiens) n'a plus d'onglet : il ne reste
/// accessible que via la loupe de l'en-tête, qui ouvre `AppRouter.appointments`
/// (#5194).
class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  late final MessagingBloc _messagingBloc;
  late final NotificationsBloc _notificationsBloc;
  late final HomeBloc _homeBloc;

  @override
  void initState() {
    super.initState();
    _messagingBloc = GetIt.instance<MessagingBloc>()
      ..add(const MessagingConversationsLoadRequested());
    _notificationsBloc = GetIt.instance<NotificationsBloc>()
      ..add(const NotificationsUnreadCountRequested());
    _homeBloc = GetIt.instance<HomeBloc>()..add(const HomeLoadRequested());
  }

  @override
  void dispose() {
    _messagingBloc.close();
    _notificationsBloc.close();
    _homeBloc.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider.value(value: _messagingBloc),
        BlocProvider.value(value: _notificationsBloc),
        BlocProvider.value(value: _homeBloc),
      ],
      child: Scaffold(
        appBar: NubiaAppBar(
          // L'onglet Accueil porte déjà sa propre salutation « Bonjour
          // <prénom> » dans le contenu (HomePage, #5195) : pas de titre de
          // barre dupliqué au-dessus (maquette `patient-accueil.png`).
          title: '',
          actions: [
            _HeaderIconButton(
              key: const Key('header_action_search'),
              icon: Icons.search,
              tooltip: 'Annuaire',
              onPressed: () => context.go(AppRouter.appointments),
            ),
            BlocSelector<NotificationsBloc, NotificationsState, bool>(
              selector: (s) =>
                  s is NotificationsUnreadCountLoaded && s.unreadCount > 0,
              builder: (context, hasUnread) => _HeaderIconButton(
                key: const Key('header_action_notifications'),
                icon: Icons.notifications_outlined,
                tooltip: 'Notifications',
                showDot: hasUnread,
                onPressed: () => context.go(AppRouter.notifications),
              ),
            ),
            const SizedBox(width: 4),
          ],
        ),
        body: const HomePage(),
        bottomNavigationBar: PatientTabBottomNav(
          selectedIndex: 0,
          onDestinationSelected: (i) => goToPatientTab(context, i, 0),
        ),
      ),
    );
  }
}

/// En-tête d'accueil : `iconbtn` 44×44 (radius 14, fond `n0`, bordure
/// `n200`, icône `n600` 22px) avec pastille rouge optionnelle (`.dot`).
class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.showDot = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool showDot;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Tooltip(
        message: tooltip,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onPressed,
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: NubiaColors.n0,
              border: Border.all(color: NubiaColors.n200),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Center(child: Icon(icon, color: NubiaColors.n600, size: 22)),
                if (showDot)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      key: const Key('header_notification_dot'),
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        color: NubiaColors.dangerFg,
                        shape: BoxShape.circle,
                        border: Border.all(color: NubiaColors.n0, width: 2),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

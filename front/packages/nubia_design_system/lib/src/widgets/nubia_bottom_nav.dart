// lib/presentation/widgets/nubia_bottom_nav.dart
import 'package:flutter/material.dart';

/// Shell de navigation principal Nubia : 5 onglets avec badge unread.
///
/// - [currentIndex] : onglet actif (0–4).
/// - [onTap] : callback déclenché à chaque tap avec le nouvel index.
/// - [unreadMessages] : nombre de messages non lus affiché en badge sur
///   l'onglet Messages (index 2). Masqué si 0.
class NubiaBottomNav extends StatelessWidget {
  const NubiaBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
    this.unreadMessages = 0,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;
  final int unreadMessages;

  @override
  Widget build(BuildContext context) {
    return NavigationBar(
      selectedIndex: currentIndex,
      onDestinationSelected: onTap,
      destinations: [
        const NavigationDestination(
          icon: Icon(Icons.home_outlined),
          selectedIcon: Icon(Icons.home),
          label: 'Accueil',
        ),
        const NavigationDestination(
          icon: Icon(Icons.calendar_today_outlined),
          selectedIcon: Icon(Icons.calendar_today),
          label: 'RDV',
        ),
        NavigationDestination(
          icon: _BadgedIcon(
            icon: Icons.chat_bubble_outline,
            badge: unreadMessages,
          ),
          selectedIcon: _BadgedIcon(
            icon: Icons.chat_bubble,
            badge: unreadMessages,
          ),
          label: 'Messages',
        ),
        const NavigationDestination(
          icon: Icon(Icons.description_outlined),
          selectedIcon: Icon(Icons.description),
          label: 'Documents',
        ),
        const NavigationDestination(
          icon: Icon(Icons.person_outline),
          selectedIcon: Icon(Icons.person),
          label: 'Profil',
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

class _BadgedIcon extends StatelessWidget {
  const _BadgedIcon({required this.icon, required this.badge});

  final IconData icon;
  final int badge;

  @override
  Widget build(BuildContext context) {
    if (badge <= 0) {
      return Icon(icon);
    }
    return Badge(
      label: Text('$badge'),
      child: Icon(icon),
    );
  }
}

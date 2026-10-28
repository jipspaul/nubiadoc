import 'package:flutter/material.dart';

/// Un onglet de la barre de navigation patient (icône + libellé).
class PatientBottomNavTab {
  const PatientBottomNavTab({
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

/// Les 5 onglets du shell patient (Accueil / Mes RDV / Messages / Documents
/// / Profil), dans l'ordre affiché par [PatientBottomNavBar].
const patientBottomNavTabs = [
  PatientBottomNavTab(
    label: 'Accueil',
    icon: Icons.home_outlined,
    selectedIcon: Icons.home,
  ),
  PatientBottomNavTab(
    label: 'Mes RDV',
    icon: Icons.event_outlined,
    selectedIcon: Icons.event_outlined,
  ),
  PatientBottomNavTab(
    label: 'Messages',
    icon: Icons.chat_bubble_outline,
    selectedIcon: Icons.chat_bubble_outline,
  ),
  PatientBottomNavTab(
    label: 'Documents',
    icon: Icons.folder_outlined,
    selectedIcon: Icons.folder_outlined,
  ),
  PatientBottomNavTab(
    label: 'Profil',
    icon: Icons.person_outline,
    selectedIcon: Icons.person_outline,
  ),
];

/// Index de l'onglet « Messages » dans [patientBottomNavTabs], seul à porter
/// un badge de compteur non-lus.
const patientBottomNavMessagesIndex = 2;

/// Barre d'onglets du shell patient — extraite de `DashboardPage` (#6694)
/// pour être réutilisée par les routes de premier niveau atteignables par
/// lien direct (ex. `/messaging`, cible du deep link de notification) qui
/// doivent offrir la même sortie que l'onglet du shell.
class PatientBottomNavBar extends StatelessWidget {
  const PatientBottomNavBar({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    this.messagesUnreadCount = 0,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final int messagesUnreadCount;

  @override
  Widget build(BuildContext context) {
    return NavigationBar(
      selectedIndex: selectedIndex,
      onDestinationSelected: onDestinationSelected,
      destinations: [
        for (int i = 0; i < patientBottomNavTabs.length; i++)
          NavigationDestination(
            icon: i == patientBottomNavMessagesIndex
                ? Badge.count(
                    count: messagesUnreadCount,
                    isLabelVisible: messagesUnreadCount > 0,
                    child: Icon(patientBottomNavTabs[i].icon),
                  )
                : Icon(patientBottomNavTabs[i].icon),
            selectedIcon: Icon(patientBottomNavTabs[i].selectedIcon),
            label: patientBottomNavTabs[i].label,
          ),
      ],
    );
  }
}

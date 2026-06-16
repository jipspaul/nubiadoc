import 'package:flutter/material.dart';

import '../pro_config.dart';

/// Mobile layout for [ProShell]: a [Drawer] accessed via an AppBar hamburger,
/// with the body occupying the full screen.
class MobileShell extends StatelessWidget {
  const MobileShell({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.body,
  });

  final List<ProNavDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: Builder(
          builder: (ctx) => IconButton(
            icon: const Icon(Icons.menu),
            tooltip: 'Menu',
            onPressed: () => Scaffold.of(ctx).openDrawer(),
          ),
        ),
      ),
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            const DrawerHeader(child: SizedBox.shrink()),
            for (var i = 0; i < destinations.length; i++)
              ListTile(
                leading: Icon(destinations[i].icon),
                title: Text(destinations[i].label),
                selected: i == selectedIndex,
                onTap: () {
                  Navigator.of(context).pop();
                  onDestinationSelected(i);
                },
              ),
          ],
        ),
      ),
      body: body,
    );
  }
}

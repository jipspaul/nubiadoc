import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../pro_config.dart';
import 'desktop_shell.dart';
import 'mobile_shell.dart';

/// Breakpoint above which the desktop (NavigationRail) layout is used.
const double _kDesktopBreakpoint = 720;

/// Shared scaffold for pro apps.
///
/// Renders a [NavigationRail] on desktop (width ≥ 720) and a [Drawer] on
/// mobile. Destinations marked [ProNavDestination.requiresClinical] are
/// hidden when [canAccessClinical] is false.
///
/// Navigation is driven by `go_router`: tapping a destination calls
/// `context.go(destination.route)`.
class ProShell extends StatefulWidget {
  const ProShell({
    super.key,
    required this.config,
    required this.canAccessClinical,
    required this.body,
  });

  final ProConfig config;
  final bool canAccessClinical;
  final Widget body;

  @override
  State<ProShell> createState() => _ProShellState();
}

class _ProShellState extends State<ProShell> {
  int _index = 0;

  List<ProNavDestination> get _visibleDestinations => widget.config.nav
      .where((d) => !d.requiresClinical || widget.canAccessClinical)
      .toList();

  void _onDestinationSelected(BuildContext context, int index) {
    final destinations = _visibleDestinations;
    if (index < 0 || index >= destinations.length) return;
    setState(() => _index = index);
    context.go(destinations[index].route);
  }

  @override
  Widget build(BuildContext context) {
    final destinations = _visibleDestinations;
    final safeIndex =
        _index.clamp(0, destinations.isEmpty ? 0 : destinations.length - 1);
    final width = MediaQuery.sizeOf(context).width;

    if (width >= _kDesktopBreakpoint) {
      return DesktopShell(
        destinations: destinations,
        selectedIndex: safeIndex,
        onDestinationSelected: (i) => _onDestinationSelected(context, i),
        body: widget.body,
      );
    }
    return MobileShell(
      destinations: destinations,
      selectedIndex: safeIndex,
      onDestinationSelected: (i) => _onDestinationSelected(context, i),
      body: widget.body,
    );
  }
}

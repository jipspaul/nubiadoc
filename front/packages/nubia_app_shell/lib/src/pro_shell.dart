import 'package:flutter/material.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

import 'config.dart';

/// Shared scaffold for the professional apps (praticien + secrétariat).
///
/// Desktop (width ≥ 720 px): [NavigationRail] on the left + content area on
/// the right.  Mobile: [Drawer] with a hamburger [AppBar].
///
/// Destinations flagged with [ProNavDestination.requiresClinical] are
/// automatically hidden when [session.canAccessClinical] is false, ensuring
/// the secretariat app never exposes clinical surfaces.
class ProShell extends StatefulWidget {
  const ProShell({
    super.key,
    required this.config,
    required this.session,
    this.bodyBuilder,
    this.trailingActions = const [],
    this.onSignOut,
  });

  final ProConfig config;
  final AuthSession session;

  /// Provides the main content widget for the selected destination.
  /// Defaults to a labelled [NubiaEmptyState] placeholder when omitted.
  final Widget Function(BuildContext context, ProNavDestination destination)?
      bodyBuilder;

  /// Extra icon-buttons rendered above the sign-out button in the rail /
  /// drawer (e.g. a demo shortcut).
  final List<Widget> trailingActions;

  final VoidCallback? onSignOut;

  @override
  State<ProShell> createState() => _ProShellState();
}

class _ProShellState extends State<ProShell> {
  int _index = 0;

  List<ProNavDestination> get _destinations => widget.config.destinations
      .where((d) => !d.requiresClinical || widget.session.canAccessClinical)
      .toList();

  @override
  Widget build(BuildContext context) {
    final destinations = _destinations;
    final index = _index.clamp(0, destinations.length - 1);
    final current = destinations[index];

    return LayoutBuilder(
      builder: (context, constraints) {
        return constraints.maxWidth >= 720
            ? _buildDesktop(context, destinations, index, current)
            : _buildMobile(context, destinations, index, current);
      },
    );
  }

  Widget _content(BuildContext context, ProNavDestination destination) {
    if (widget.bodyBuilder != null) {
      return widget.bodyBuilder!(context, destination);
    }
    return Center(
      child: NubiaEmptyState(
        icon: Icons.construction_outlined,
        title: destination.label,
      ),
    );
  }

  Widget _trailing(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ...widget.trailingActions,
        if (widget.onSignOut != null)
          IconButton(
            tooltip: 'Se déconnecter',
            icon: const Icon(Icons.logout),
            onPressed: widget.onSignOut,
          ),
      ],
    );
  }

  Widget _buildDesktop(
    BuildContext context,
    List<ProNavDestination> destinations,
    int index,
    ProNavDestination current,
  ) {
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: index,
            onDestinationSelected: (i) => setState(() => _index = i),
            labelType: NavigationRailLabelType.all,
            leading: const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: FlutterLogo(),
            ),
            trailing: Expanded(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _trailing(context),
                ),
              ),
            ),
            destinations: [
              for (final d in destinations)
                NavigationRailDestination(
                  icon: Icon(d.icon),
                  label: Text(d.label),
                ),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: Scaffold(
              appBar: NubiaAppBar(title: current.label, centerTitle: false),
              body: _content(context, current),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobile(
    BuildContext context,
    List<ProNavDestination> destinations,
    int index,
    ProNavDestination current,
  ) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.config.appTitle)),
      drawer: Drawer(
        child: SafeArea(
          child: Column(
            children: [
              ListTile(
                title: Text(
                  widget.config.spaceLabel,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              const Divider(),
              for (int i = 0; i < destinations.length; i++)
                ListTile(
                  leading: Icon(destinations[i].icon),
                  title: Text(destinations[i].label),
                  selected: i == index,
                  onTap: () {
                    Navigator.of(context).pop();
                    setState(() => _index = i);
                  },
                ),
              const Spacer(),
              _trailing(context),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
      body: _content(context, current),
    );
  }
}

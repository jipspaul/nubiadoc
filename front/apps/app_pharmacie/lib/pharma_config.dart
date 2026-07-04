import 'package:flutter/material.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_app_shell/nubia_app_shell.dart' as shell;

/// App-level constants for the pharmacie app.
///
/// [role] seeds a stub [AuthSession] until `GET /v1/me` +
/// `POST /v1/auth/select-pharmacy-context` sont câblés dans le cubit.
/// Aucune destination `requiresClinical` : la pharmacie n'a AUCUN accès
/// clinique (elle ne voit que le PDF signé de ses commandes).
class PharmaConfig {
  const PharmaConfig._();

  static const String appTitle = 'Nubia · Pharmacie';
  static const String spaceLabel = 'Espace pharmacie';

  static const ProRole role = ProRole.pharmacist;

  static const String ordersRoute = '/';

  static const shell.ProConfig shellConfig = shell.ProConfig(
    appTitle: appTitle,
    spaceLabel: spaceLabel,
    destinations: [
      shell.ProNavDestination(
        label: 'Commandes',
        icon: Icons.shopping_bag_outlined,
        route: ordersRoute,
      ),
      shell.ProNavDestination(
        label: 'Stock',
        icon: Icons.inventory_2_outlined,
        route: '/stock',
      ),
      shell.ProNavDestination(
        label: 'Messages',
        icon: Icons.chat_bubble_outline,
        route: '/messages',
      ),
      shell.ProNavDestination(
        label: 'Devis',
        icon: Icons.receipt_long_outlined,
        route: '/devis',
      ),
    ],
  );
}

// lib/presentation/widgets/nubia_app_bar.dart
import 'package:flutter/material.dart';

/// AppBar Nubia standard.
///
/// Wraps [AppBar] avec le style Nubia (fond `surface`, couleur primaire pour
/// les icônes d'action, titre centré sur mobile).
///
/// - [title] : titre affiché dans la barre.
/// - [actions] : liste de widgets d'action optionnels (icônes, avatars…).
/// - [leading] : widget leading optionnel (remplace la flèche retour par défaut).
/// - [centerTitle] : centre le titre (défaut true).
class NubiaAppBar extends StatelessWidget implements PreferredSizeWidget {
  const NubiaAppBar({
    super.key,
    required this.title,
    this.actions,
    this.leading,
    this.centerTitle = true,
  });

  final String title;
  final List<Widget>? actions;
  final Widget? leading;
  final bool centerTitle;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AppBar(
      backgroundColor: cs.surface,
      foregroundColor: cs.onSurface,
      surfaceTintColor: Colors.transparent,
      centerTitle: centerTitle,
      leading: leading,
      title: Text(
        title,
        style: Theme.of(context).textTheme.titleLarge,
      ),
      actions: actions,
    );
  }
}

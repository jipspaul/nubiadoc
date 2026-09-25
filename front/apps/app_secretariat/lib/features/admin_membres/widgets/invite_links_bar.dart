import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';
import 'package:share_plus/share_plus.dart';

import '../invite_links_cubit.dart';

/// Rôles éligibles au lien d'invitation copiable — sous-ensemble de
/// [MemberRole] accepté par `POST /v1/cabinet/invite-links` (#7148) : le
/// back n'y reconnaît pas `assistant` (`VALID_ROLES` de
/// `cabinet_invite_links.rs`), qui reste réservé à l'invitation nominative
/// par e-mail ([InviteMemberDialog]).
const _inviteLinkRoles = [
  MemberRole.practitioner,
  MemberRole.secretary,
  MemberRole.admin,
];

String _roleLabel(MemberRole role) => switch (role) {
      MemberRole.practitioner => 'Praticien',
      MemberRole.secretary => 'Secrétaire',
      MemberRole.admin => 'Admin',
      MemberRole.assistant => 'Assistant',
    };

/// Boutons « copier le lien d'invitation » par rôle (#7147) : génère un lien
/// à usage multiple côté back, le copie dans le presse-papiers puis propose
/// le partage système via `share_plus`.
class InviteLinksBar extends StatelessWidget {
  const InviteLinksBar({super.key});

  Future<void> _copy(BuildContext context, MemberRole role) async {
    final link = await context.read<InviteLinksCubit>().generate(role);
    if (link == null || !context.mounted) return;
    await Clipboard.setData(ClipboardData(text: link.url));
    if (!context.mounted) return;
    NubiaSnackbar.show(
      context: context,
      message: 'Lien copié — ${_roleLabel(role)}.',
      actionLabel: 'Partager',
      onAction: () => Share.share(
        link.url,
        subject: 'Invitation Nubia — ${_roleLabel(role)}',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<InviteLinksCubit, InviteLinksState>(
      builder: (context, state) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final role in _inviteLinkRoles)
              NubiaButton(
                key: Key('invite_link_button_${role.name}'),
                label: 'Lien — ${_roleLabel(role)}',
                icon: Icons.link,
                size: NubiaButtonSize.sm,
                variant: NubiaButtonVariant.secondary,
                isLoading: state.pendingRole == role,
                onPressed: () => _copy(context, role),
              ),
          ],
        ),
      ),
    );
  }
}

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import '../../router/app_router.dart';
import '../../session/auth_cubit.dart';
import 'profile_bloc.dart';
import 'profile_event.dart';
import 'profile_state.dart';

/// Profile body — must be placed inside a [BlocProvider<ProfileBloc>].
///
/// Displays account header, personal info, and navigation tiles for
/// coverage, dependents, consents, and notification preferences.
///
/// The caller is responsible for adding [ProfileLoadRequested] to the bloc
/// (typically via `..add(const ProfileLoadRequested())` in the BlocProvider's
/// `create` callback).
class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<ProfileBloc, ProfileState>(
      listenWhen: (_, current) => current is ProfileToggleFailed,
      listener: (context, state) {
        if (state is ProfileToggleFailed) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(state.message)),
          );
        }
      },
      builder: (context, state) {
        if (state is ProfileInitial || state is ProfileLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        if (state is ProfileError) {
          return NubiaErrorWidget(
            message: state.message,
            onRetry: () =>
                context.read<ProfileBloc>().add(const ProfileLoadRequested()),
          );
        }
        if (state is ProfileLoaded) {
          return _ProfileContent(
            account: state.account,
            biometricEnabled: state.biometricEnabled,
            emailRdv: state.notifPrefs?.emailEnabled ?? true,
            pushRdv: state.notifPrefs?.pushEnabled ?? true,
          );
        }
        if (state is ProfileToggleFailed) {
          return _ProfileContent(
            account: state.previousState.account,
            biometricEnabled: state.previousState.biometricEnabled,
            emailRdv: state.previousState.notifPrefs?.emailEnabled ?? true,
            pushRdv: state.previousState.notifPrefs?.pushEnabled ?? true,
          );
        }
        return const SizedBox.shrink();
      },
    );
  }
}

// ---------------------------------------------------------------------------

class _ProfileContent extends StatelessWidget {
  const _ProfileContent({
    required this.account,
    required this.biometricEnabled,
    required this.emailRdv,
    required this.pushRdv,
  });

  final PatientAccount account;
  final bool biometricEnabled;
  final bool emailRdv;
  final bool pushRdv;

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: const Key('profile_content'),
      children: [
        _ProfileHeader(account: account),
        const Divider(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            'Informations personnelles',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ),
        _InfoRow(label: 'Email', value: account.email),
        if (account.phone != null && account.phone!.isNotEmpty)
          _InfoRow(label: 'Téléphone', value: account.phone!),
        const Divider(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            'Mon compte',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ),
        _SectionTile(
          key: const Key('tile_coverage'),
          icon: Icons.health_and_safety_outlined,
          title: 'Couverture santé',
          onTap: () => context.push(AppRouter.coverageSetup),
        ),
        _SectionTile(
          key: const Key('tile_dependents'),
          icon: Icons.people_outline,
          title: 'Mes proches',
          onTap: () => context.push(AppRouter.profileDependents),
        ),
        _SectionTile(
          key: const Key('tile_consents'),
          icon: Icons.verified_user_outlined,
          title: 'Consentements',
          onTap: () => context.push(AppRouter.profileConsents),
        ),
        _SectionTile(
          key: const Key('tile_notifications'),
          icon: Icons.notifications_outlined,
          title: 'Préférences notifications',
          onTap: () => context.push(AppRouter.profileNotifications),
        ),
        const Divider(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            'Notifications RDV',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ),
        SwitchListTile(
          key: const Key('email_rdv_toggle'),
          secondary: const Icon(Icons.email_outlined),
          title: const Text('Rappels e-mail'),
          value: emailRdv,
          onChanged: (v) =>
              context.read<ProfileBloc>().add(ToggleEmailRdv(enabled: v)),
        ),
        SwitchListTile(
          key: const Key('push_rdv_toggle'),
          secondary: const Icon(Icons.notifications_outlined),
          title: const Text('Notifications push'),
          value: pushRdv,
          onChanged: (v) =>
              context.read<ProfileBloc>().add(TogglePushRdv(enabled: v)),
        ),
        const Divider(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            'Sécurité',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ),
        SwitchListTile(
          key: const Key('biometric_toggle'),
          secondary: const Icon(Icons.fingerprint),
          title: const Text('Authentification biométrique'),
          value: biometricEnabled,
          onChanged: (v) => context
              .read<ProfileBloc>()
              .add(BiometricToggleRequested(enabled: v)),
        ),
        const Divider(),
        const _LogoutTile(),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.account});

  final PatientAccount account;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      child: Row(
        children: [
          _AvatarPicker(initials: _initials(account)),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  account.displayName,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  account.email,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _initials(PatientAccount account) {
    final first =
        account.firstName.isNotEmpty ? account.firstName[0].toUpperCase() : '';
    final last =
        account.lastName.isNotEmpty ? account.lastName[0].toUpperCase() : '';
    return '$first$last';
  }
}

// ---------------------------------------------------------------------------

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
          Expanded(
            child: Text(value, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _SectionTile extends StatelessWidget {
  const _SectionTile({
    super.key,
    required this.icon,
    required this.title,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}

// ---------------------------------------------------------------------------

class _LogoutTile extends StatelessWidget {
  const _LogoutTile();

  @override
  Widget build(BuildContext context) {
    return ListTile(
      key: const Key('logout_tile'),
      leading: Icon(Icons.logout, color: Theme.of(context).colorScheme.error),
      title: Text(
        'Se déconnecter',
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      ),
      onTap: () => context.read<AuthCubit>().signOut(),
    );
  }
}

// ---------------------------------------------------------------------------

/// Avatar cliquable : charge la photo de profil (GET /account/avatar), affiche
/// l'image ou les initiales, et permet d'en téléverser une nouvelle
/// (PUT /account/avatar). Autonome — ne dépend pas du ProfileBloc.
class _AvatarPicker extends StatefulWidget {
  const _AvatarPicker({required this.initials});
  final String initials;

  @override
  State<_AvatarPicker> createState() => _AvatarPickerState();
}

class _AvatarPickerState extends State<_AvatarPicker> {
  Uint8List? _bytes;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // Tolérant aux harness de test qui n'enregistrent pas ce use case :
    // l'avatar est une amélioration, pas un prérequis du header.
    if (!GetIt.instance.isRegistered<GetAvatarUseCase>()) return;
    final result = await GetIt.instance<GetAvatarUseCase>().call();
    if (!mounted) return;
    result.fold(
      (_) {},
      (avatar) => setState(() => _bytes =
          avatar == null ? null : Uint8List.fromList(avatar.bytes)),
    );
  }

  Future<void> _pickAndUpload() async {
    if (!GetIt.instance.isRegistered<FilePickerService>() ||
        !GetIt.instance.isRegistered<UpdateAvatarUseCase>()) {
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    final picked = await GetIt.instance<FilePickerService>().pickFile(
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp'],
    );
    if (picked == null || !mounted) return;

    // MIME déterminé par les octets magiques (fiable), pas par l'extension :
    // sur le web, file_picker renvoie souvent un type générique qui fait
    // échouer l'upload (422). Voir aussi l'API qui n'accepte que JPEG/PNG/WebP.
    final mime = _detectImageMime(picked.bytes);
    if (mime == null) {
      messenger.showSnackBar(const SnackBar(
        content: Text('Format non supporté. Choisissez une image JPEG, PNG ou WebP.'),
      ));
      return;
    }
    if (picked.bytes.lengthInBytes > 300 * 1024) {
      messenger.showSnackBar(const SnackBar(
        content: Text('Image trop lourde (300 Ko max).'),
      ));
      return;
    }

    setState(() => _busy = true);
    final result = await GetIt.instance<UpdateAvatarUseCase>().call(
      bytes: picked.bytes,
      mimeType: mime,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    result.fold(
      (f) => messenger.showSnackBar(SnackBar(content: Text(f.message))),
      (_) => setState(() => _bytes = picked.bytes),
    );
  }

  /// Détecte le type MIME d'une image par sa signature (magic bytes), pour ne
  /// pas dépendre de l'extension (peu fiable sur Flutter web). Null si ce n'est
  /// pas une image supportée.
  static String? _detectImageMime(Uint8List b) {
    if (b.length >= 8 &&
        b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47) {
      return 'image/png';
    }
    if (b.length >= 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) {
      return 'image/jpeg';
    }
    if (b.length >= 12 &&
        b[0] == 0x52 && b[1] == 0x49 && b[2] == 0x46 && b[3] == 0x46 && // RIFF
        b[8] == 0x57 && b[9] == 0x45 && b[10] == 0x42 && b[11] == 0x50) {
      return 'image/webp';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: 'Modifier la photo de profil',
      child: InkWell(
        key: const Key('avatar_picker'),
        onTap: _busy ? null : _pickAndUpload,
        customBorder: const CircleBorder(),
        child: Stack(
          alignment: Alignment.center,
          children: [
            CircleAvatar(
              radius: 32,
              backgroundColor: colorScheme.primaryContainer,
              backgroundImage:
                  _bytes != null ? MemoryImage(_bytes!) : null,
              child: _bytes != null
                  ? null
                  : Text(
                      widget.initials,
                      style: TextStyle(
                        color: colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.bold,
                        fontSize: 20,
                      ),
                    ),
            ),
            if (_busy)
              const SizedBox(
                width: 64,
                height: 64,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            Positioned(
              right: 0,
              bottom: 0,
              child: CircleAvatar(
                radius: 11,
                backgroundColor: colorScheme.primary,
                child: Icon(Icons.photo_camera,
                    size: 13, color: colorScheme.onPrimary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

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
          return const _ProfileSkeleton();
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
            phoneUpdating: state.phoneUpdating,
          );
        }
        if (state is ProfileToggleFailed) {
          return _ProfileContent(
            account: state.previousState.account,
            biometricEnabled: state.previousState.biometricEnabled,
            emailRdv: state.previousState.notifPrefs?.emailEnabled ?? true,
            pushRdv: state.previousState.notifPrefs?.pushEnabled ?? true,
            phoneUpdating: false,
          );
        }
        return const SizedBox.shrink();
      },
    );
  }
}

// ---------------------------------------------------------------------------

class _ProfileSkeleton extends StatelessWidget {
  const _ProfileSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: const Key('profile_loading'),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: const [
        _ProfileHeaderSkeleton(),
        SizedBox(height: 24),
        NubiaSkeletonLoader(height: 16, width: 160),
        SizedBox(height: 12),
        _ProfileSectionSkeleton(rows: 2),
        SizedBox(height: 24),
        NubiaSkeletonLoader(height: 16, width: 140),
        SizedBox(height: 12),
        _ProfileSectionSkeleton(rows: 2),
        SizedBox(height: 24),
        NubiaSkeletonLoader(height: 16, width: 100),
        SizedBox(height: 12),
        _ProfileSectionSkeleton(rows: 1),
      ],
    );
  }
}

class _ProfileHeaderSkeleton extends StatelessWidget {
  const _ProfileHeaderSkeleton();

  @override
  Widget build(BuildContext context) {
    return const NubiaCard(
      padding: EdgeInsets.all(20),
      child: Row(
        children: [
          NubiaSkeletonLoader(height: 64, width: 64, borderRadius: 32),
          SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                NubiaSkeletonLoader(height: 16, width: 140),
                SizedBox(height: 8),
                NubiaSkeletonLoader(height: 12, width: 180),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileSectionSkeleton extends StatelessWidget {
  const _ProfileSectionSkeleton({required this.rows});

  final int rows;

  @override
  Widget build(BuildContext context) {
    return NubiaCard(
      child: Column(
        children: [
          for (var i = 0; i < rows; i++) ...[
            if (i > 0) const SizedBox(height: 12),
            const Row(
              children: [
                NubiaSkeletonLoader(height: 20, width: 20, borderRadius: 4),
                SizedBox(width: 12),
                Expanded(child: NubiaSkeletonLoader(height: 14)),
              ],
            ),
          ],
        ],
      ),
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
    required this.phoneUpdating,
  });

  final PatientAccount account;
  final bool biometricEnabled;
  final bool emailRdv;
  final bool pushRdv;
  final bool phoneUpdating;

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: const Key('profile_content'),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        _ProfileHeaderCard(account: account),
        const SizedBox(height: 24),
        const _SectionLabel(label: 'Informations personnelles'),
        const SizedBox(height: 12),
        NubiaCard(
          child: Column(
            children: [
              _InfoRow(label: 'Email', value: account.email),
              const SizedBox(height: 12),
              _PhoneRow(phone: account.phone, updating: phoneUpdating),
            ],
          ),
        ),
        const SizedBox(height: 24),
        const _SectionLabel(label: 'Notifications RDV'),
        const SizedBox(height: 12),
        NubiaCard(
          child: Column(
            children: [
              _ToggleRow(
                toggleKey: const Key('email_rdv_toggle'),
                icon: Icons.email_outlined,
                title: 'Rappels e-mail',
                value: emailRdv,
                onChanged: (v) =>
                    context.read<ProfileBloc>().add(ToggleEmailRdv(enabled: v)),
              ),
              const SizedBox(height: 4),
              _ToggleRow(
                toggleKey: const Key('push_rdv_toggle'),
                icon: Icons.notifications_active_outlined,
                title: 'Notifications push',
                value: pushRdv,
                onChanged: (v) =>
                    context.read<ProfileBloc>().add(TogglePushRdv(enabled: v)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        const _SectionLabel(label: 'Sécurité'),
        const SizedBox(height: 12),
        NubiaCard(
          child: _ToggleRow(
            toggleKey: const Key('biometric_toggle'),
            icon: Icons.fingerprint,
            title: 'Authentification biométrique',
            value: biometricEnabled,
            onChanged: (v) => context
                .read<ProfileBloc>()
                .add(BiometricToggleRequested(enabled: v)),
          ),
        ),
        const SizedBox(height: 24),
        const _SectionLabel(label: 'Mon compte'),
        const SizedBox(height: 12),
        NubiaCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              ListRow(
                key: const Key('tile_financial'),
                leading: const Icon(Icons.receipt_long_outlined),
                title: 'Mes devis & paiements',
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push(AppRouter.financial),
              ),
              ListRow(
                key: const Key('tile_coverage'),
                leading: const Icon(Icons.health_and_safety_outlined),
                title: 'Couverture santé',
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push(AppRouter.coverageSetup),
              ),
              ListRow(
                key: const Key('tile_referring_doctor'),
                leading: const Icon(Icons.medical_services_outlined),
                title: 'Médecin traitant',
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push(AppRouter.profileReferringDoctor),
              ),
              ListRow(
                key: const Key('tile_dependents'),
                leading: const Icon(Icons.people_outline),
                title: 'Mes proches',
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push(AppRouter.profileDependents),
              ),
              ListRow(
                key: const Key('tile_consents'),
                leading: const Icon(Icons.verified_user_outlined),
                title: 'Consentements',
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push(AppRouter.profileConsents),
              ),
              ListRow(
                key: const Key('tile_implant_passport'),
                leading: const Icon(Icons.medical_information_outlined),
                title: 'Passeport implantaire',
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push(AppRouter.implantPassport),
              ),
              ListRow(
                key: const Key('tile_notifications'),
                leading: const Icon(Icons.notifications_outlined),
                title: 'Préférences notifications',
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push(AppRouter.profileNotifications),
              ),
              ListRow(
                key: const Key('tile_pharmacy'),
                leading: const Icon(Icons.local_pharmacy_outlined),
                title: 'Ma pharmacie',
                trailing: const Icon(Icons.chevron_right),
                showDivider: false,
                onTap: () => context.push('/pharmacy'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: NubiaButton(
            key: const Key('logout_tile'),
            label: 'Se déconnecter',
            icon: Icons.logout,
            variant: NubiaButtonVariant.destructive,
            onPressed: () => context.read<AuthCubit>().signOut(),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Text(
      label,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
            color: cs.onSurface,
            fontWeight: FontWeight.w600,
          ),
    );
  }
}

// ---------------------------------------------------------------------------

class _ProfileHeaderCard extends StatelessWidget {
  const _ProfileHeaderCard({required this.account});

  final PatientAccount account;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return NubiaCard(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          _AvatarPicker(initials: _initials(account)),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(account.displayName, style: textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  account.email,
                  style:
                      textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
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

/// #4544 : l'email n'est jamais modifiable via `PATCH /v1/account` (422 si
/// présent dans le corps — modifiable uniquement via le flow de connexion).
/// Un champ de saisie désactivé pour une valeur définitivement figée est
/// trompeur (ressemble à un formulaire cassé) : simple affichage texte.
class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
        const SizedBox(height: 2),
        Text(value,
            key: const Key('profile_email_value'), style: textTheme.bodyLarge),
      ],
    );
  }
}

/// #4544 : le téléphone, contrairement à l'email, EST modifiable côté back
/// (`PATCH /v1/account` accepte `phone`) — l'écran n'offrait pourtant aucun
/// moyen de le faire. Affichage + bouton crayon ouvrant un dialog d'édition.
class _PhoneRow extends StatelessWidget {
  const _PhoneRow({required this.phone, required this.updating});

  final String? phone;
  final bool updating;

  Future<void> _edit(BuildContext context) async {
    final bloc = context.read<ProfileBloc>();
    final controller = TextEditingController(text: phone ?? '');
    final newPhone = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Modifier le téléphone'),
        content: TextField(
          key: const Key('edit_phone_field'),
          controller: controller,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
            hintText: '+33612345678',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            key: const Key('cancel_phone_edit_button'),
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Annuler'),
          ),
          FilledButton(
            key: const Key('save_phone_button'),
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
    if (newPhone != null && newPhone.isNotEmpty && newPhone != phone) {
      bloc.add(PhoneUpdateRequested(newPhone));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Téléphone',
                  style: textTheme.labelSmall
                      ?.copyWith(color: cs.onSurfaceVariant)),
              const SizedBox(height: 2),
              Text(
                phone != null && phone!.isNotEmpty ? phone! : 'Non renseigné',
                key: const Key('profile_phone_value'),
                style: textTheme.bodyLarge,
              ),
            ],
          ),
        ),
        if (updating)
          const Padding(
            padding: EdgeInsets.all(8),
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        else
          IconButton(
            key: const Key('edit_phone_button'),
            tooltip: 'Modifier le téléphone',
            icon: const Icon(Icons.edit_outlined, size: 20),
            onPressed: () => _edit(context),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

/// Ligne de réglage : pastille icône + libellé + [NubiaToggle].
class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.toggleKey,
    required this.icon,
    required this.title,
    required this.value,
    required this.onChanged,
  });

  final Key toggleKey;
  final IconData icon;
  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Row(
      children: [
        Icon(icon, size: 20, color: cs.onSurfaceVariant),
        const SizedBox(width: 12),
        Expanded(
          child: Text(title, style: textTheme.bodyLarge),
        ),
        NubiaToggle(key: toggleKey, value: value, onChanged: onChanged),
      ],
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
      (avatar) => setState(() =>
          _bytes = avatar == null ? null : Uint8List.fromList(avatar.bytes)),
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
        content: Text(
            'Format non supporté. Choisissez une image JPEG, PNG ou WebP.'),
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
        b[0] == 0x89 &&
        b[1] == 0x50 &&
        b[2] == 0x4E &&
        b[3] == 0x47) {
      return 'image/png';
    }
    if (b.length >= 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) {
      return 'image/jpeg';
    }
    if (b.length >= 12 &&
        b[0] == 0x52 &&
        b[1] == 0x49 &&
        b[2] == 0x46 &&
        b[3] == 0x46 && // RIFF
        b[8] == 0x57 &&
        b[9] == 0x45 &&
        b[10] == 0x42 &&
        b[11] == 0x50) {
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
              backgroundImage: _bytes != null ? MemoryImage(_bytes!) : null,
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

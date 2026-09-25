import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

import '../../router/app_router.dart';
import '../../session/pro_auth_cubit.dart';
import 'provider_stamp_cubit.dart';
import 'widgets/provider_stamp_step.dart';

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({
    super.key,
    required this.invitationToken,
    this.inviteLinkToken,
  });

  final String? invitationToken;

  /// Jeton d'un lien d'invitation par rôle (#7628,
  /// `POST /v1/cabinet/invite-links`) — alternative à [invitationToken] :
  /// crée un nouveau compte pro plutôt que de finaliser un compte existant.
  final String? inviteLinkToken;

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _cguAccepted = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      _email.text.trim().isNotEmpty &&
      _password.text.isNotEmpty &&
      _cguAccepted;

  Widget _invalidInviteScreen(BuildContext context) => Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                key: Key('onboarding_invalid_token'),
                'Invitation invalide',
              ),
              const SizedBox(height: 16),
              NubiaButton(
                key: const Key('onboarding_back_button'),
                label: 'Retour à la connexion',
                onPressed: () => context.go(AppRouter.login),
              ),
            ],
          ),
        ),
      );

  bool get _hasInvitationToken =>
      widget.invitationToken != null && widget.invitationToken!.isNotEmpty;
  bool get _hasInviteLinkToken =>
      widget.inviteLinkToken != null && widget.inviteLinkToken!.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    if (!_hasInvitationToken && !_hasInviteLinkToken) {
      return _invalidInviteScreen(context);
    }

    return BlocBuilder<ProAuthCubit, AuthState>(
      builder: (context, state) {
        if (state is AuthUnauthenticated && state.invalidInvite) {
          return _invalidInviteScreen(context);
        }
        if (state is AuthAuthenticated) {
          return _profileSetupScreen(context);
        }
        return _buildForm(context, state);
      },
    );
  }

  /// Étape finale, affichée après création du compte (#7148/#7147) :
  /// signature/tampon optionnels avant de rejoindre le shell — cf.
  /// `ProviderStampStep`.
  Widget _profileSetupScreen(BuildContext context) => Scaffold(
        key: const Key('onboarding_profile_setup_scaffold'),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: BlocProvider(
                create: (_) => GetIt.instance<ProviderStampCubit>(),
                child: ProviderStampStep(
                  onDone: () => context.go(AppRouter.home),
                ),
              ),
            ),
          ),
        ),
      );

  Widget _buildForm(BuildContext context, AuthState state) {
    final loading = state is AuthLoading;
    return Scaffold(
      key: const Key('onboarding_scaffold'),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Nubia',
                    style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: 4),
                Text('Finaliser mon compte',
                    style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: 24),
                NubiaTextField(
                  key: const Key('onboarding_email_field'),
                  controller: _email,
                  label: 'E-mail professionnel',
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                NubiaTextField(
                  key: const Key('onboarding_password_field'),
                  controller: _password,
                  label: 'Mot de passe',
                  variant: NubiaTextFieldVariant.password,
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                CheckboxListTile(
                  key: const Key('onboarding_cgu_checkbox'),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text(
                      "J'accepte les conditions générales d'utilisation"),
                  value: _cguAccepted,
                  onChanged: (v) => setState(() => _cguAccepted = v ?? false),
                ),
                if (state is AuthUnauthenticated && state.message != null) ...[
                  const SizedBox(height: 12),
                  Text(state.message!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error)),
                ],
                const SizedBox(height: 24),
                NubiaButton(
                  key: const Key('onboarding_submit_button'),
                  label: 'Finaliser mon compte',
                  isLoading: loading,
                  onPressed: (!loading && _canSubmit)
                      ? () => _hasInvitationToken
                          ? context.read<ProAuthCubit>().registerWithInvitation(
                                email: _email.text.trim(),
                                password: _password.text,
                                inviteToken: widget.invitationToken!,
                                acceptCgu: _cguAccepted,
                              )
                          : context.read<ProAuthCubit>().registerWithInviteLink(
                                email: _email.text.trim(),
                                password: _password.text,
                                inviteLinkToken: widget.inviteLinkToken!,
                                acceptCgu: _cguAccepted,
                              )
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

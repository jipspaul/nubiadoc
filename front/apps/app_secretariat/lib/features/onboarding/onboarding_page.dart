import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

import '../../router/app_router.dart';
import '../../session/pro_auth_cubit.dart';

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key, required this.invitationToken});

  final String? invitationToken;

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

  @override
  Widget build(BuildContext context) {
    if (widget.invitationToken == null || widget.invitationToken!.isEmpty) {
      return _invalidInviteScreen(context);
    }

    return BlocConsumer<ProAuthCubit, AuthState>(
      listener: (context, state) {
        if (state is AuthAuthenticated) {
          context.go(AppRouter.home);
        }
      },
      builder: (context, state) {
        if (state is AuthUnauthenticated && state.invalidInvite) {
          return _invalidInviteScreen(context);
        }
        return _buildForm(context, state);
      },
    );
  }

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
                Row(
                  children: [
                    Checkbox(
                      key: const Key('onboarding_cgu_checkbox'),
                      value: _cguAccepted,
                      onChanged: (v) =>
                          setState(() => _cguAccepted = v ?? false),
                    ),
                    const Expanded(
                      child: Text(
                          "J'accepte les conditions générales d'utilisation"),
                    ),
                  ],
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
                      ? () =>
                          context.read<ProAuthCubit>().registerWithInvitation(
                                email: _email.text.trim(),
                                password: _password.text,
                                inviteToken: widget.invitationToken!,
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

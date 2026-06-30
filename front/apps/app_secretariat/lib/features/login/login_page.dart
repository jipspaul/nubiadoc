import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

import '../../pro_config.dart';
import '../../session/pro_auth_cubit.dart';

class _InvitationHelpCard extends StatelessWidget {
  const _InvitationHelpCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      key: const Key('login_invitation_help_card'),
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline,
                color: Theme.of(context).colorScheme.primary, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Pas de compte ?',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    "Le compte secrétariat se crée sur invitation par le praticien. "
                    "Si vous avez reçu un lien d'invitation par email, ouvrez-le pour finaliser votre inscription.",
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Professional login (shared backend `POST /v1/auth/login`).
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('login_scaffold'),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: BlocBuilder<ProAuthCubit, AuthState>(
            builder: (context, state) {
              final loading = state is AuthLoading;
              return SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Nubia',
                        style: Theme.of(context).textTheme.headlineMedium),
                    const SizedBox(height: 4),
                    Text(ProConfig.spaceLabel,
                        style: Theme.of(context).textTheme.bodyMedium),
                    const SizedBox(height: 24),
                    NubiaTextField(
                        controller: _email, label: 'E-mail professionnel'),
                    const SizedBox(height: 12),
                    NubiaTextField(
                      controller: _password,
                      label: 'Mot de passe',
                      variant: NubiaTextFieldVariant.password,
                    ),
                    if (state is AuthUnauthenticated &&
                        state.message != null) ...[
                      const SizedBox(height: 12),
                      Text(state.message!,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error)),
                    ],
                    const SizedBox(height: 24),
                    NubiaButton(
                      label: 'Se connecter',
                      isLoading: loading,
                      onPressed: loading
                          ? null
                          : () => context.read<ProAuthCubit>().signIn(
                                email: _email.text.trim(),
                                password: _password.text,
                              ),
                    ),
                    const SizedBox(height: 24),
                    const _InvitationHelpCard(),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

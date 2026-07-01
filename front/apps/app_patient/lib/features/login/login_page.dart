import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

import '../../session/auth_cubit.dart';

/// Minimal email/password login wired to [AuthCubit] → shared LoginUseCase.
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  // BUG-02 (issue #2563/#2580) : pré-remplissage limité au mode debug pour
  // que les builds release laissent le champ vide (sinon l'utilisateur qui
  // tape sans effacer envoie l'e-mail démo et échoue le login).
  final _email =
      TextEditingController(text: kDebugMode ? 'camille@example.com' : '');
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
          child: BlocBuilder<AuthCubit, AuthState>(
            builder: (context, state) {
              final (loading, errorMessage) = switch (state) {
                AuthUnknown() => (false, null as String?),
                AuthLoading() => (true, null),
                AuthAuthenticated() => (false, null),
                AuthUnauthenticated(:final message) => (false, message),
              };
              return SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Nubia',
                        style: Theme.of(context).textTheme.headlineMedium),
                    const SizedBox(height: 4),
                    Text('Espace patient',
                        style: Theme.of(context).textTheme.bodyMedium),
                    const SizedBox(height: 24),
                    NubiaTextField(
                      controller: _email,
                      label: 'E-mail',
                    ),
                    const SizedBox(height: 12),
                    NubiaTextField(
                      controller: _password,
                      label: 'Mot de passe',
                      variant: NubiaTextFieldVariant.password,
                    ),
                    if (errorMessage != null) ...[
                      const SizedBox(height: 12),
                      Text(errorMessage,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error)),
                    ],
                    const SizedBox(height: 24),
                    NubiaButton(
                      key: const Key('login_button'),
                      label: 'Se connecter',
                      isLoading: loading,
                      onPressed: loading
                          ? null
                          : () => context.read<AuthCubit>().signIn(
                                email: _email.text.trim(),
                                password: _password.text,
                              ),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        key: const Key('forgot_password_link'),
                        onPressed: () => context.go('/forgot-password'),
                        child: const Text('Mot de passe oublié ?'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        const Text('Pas encore de compte ?'),
                        TextButton(
                          key: const Key('signup_link'),
                          onPressed: () => context.go('/signup'),
                          child: Text(
                            'Créer mon compte',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
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

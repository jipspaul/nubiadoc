import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

import 'forgot_password_cubit.dart';

class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final _email = TextEditingController();

  static final _emailRe = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  bool get _emailValid => _emailRe.hasMatch(_email.text.trim());

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('forgot_password_scaffold'),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: BlocBuilder<ForgotPasswordCubit, ForgotPasswordState>(
            builder: (context, state) {
              final loading = state is ForgotPasswordLoading;
              final sent = state is ForgotPasswordSent;
              return SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Mot de passe oublié',
                        style: Theme.of(context).textTheme.headlineMedium),
                    const SizedBox(height: 4),
                    Text(
                      'Indiquez votre e-mail, nous vous enverrons un lien de réinitialisation.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 24),
                    if (sent) ...[
                      Text(
                        key: const Key('forgot_password_confirmation'),
                        'Si un compte existe avec cet e-mail, un message vient de lui être envoyé.',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ] else ...[
                      NubiaTextField(
                        controller: _email,
                        label: 'E-mail',
                        errorText: _email.text.trim().isNotEmpty && !_emailValid
                            ? 'E-mail invalide.'
                            : null,
                        onChanged: (_) => setState(() {}),
                      ),
                      if (state is ForgotPasswordFailure) ...[
                        const SizedBox(height: 12),
                        Text(state.message,
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.error)),
                      ],
                      const SizedBox(height: 24),
                      NubiaButton(
                        key: const Key('forgot_password_submit'),
                        label: 'Envoyer le lien',
                        isLoading: loading,
                        onPressed: (loading || !_emailValid)
                            ? null
                            : () => context
                                .read<ForgotPasswordCubit>()
                                .submit(_email.text.trim()),
                      ),
                    ],
                    const SizedBox(height: 16),
                    TextButton(
                      key: const Key('back_to_login_link'),
                      onPressed: () => context.go('/login'),
                      child: const Text('Retour à la connexion'),
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

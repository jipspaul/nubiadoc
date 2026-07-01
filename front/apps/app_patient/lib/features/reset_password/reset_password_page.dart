import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

import 'reset_password_cubit.dart';

class ResetPasswordPage extends StatefulWidget {
  const ResetPasswordPage({super.key, required this.token});

  final String? token;

  @override
  State<ResetPasswordPage> createState() => _ResetPasswordPageState();
}

class _ResetPasswordPageState extends State<ResetPasswordPage> {
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();

  bool get _passwordValid =>
      _password.text.length >= 8 && RegExp(r'[0-9]').hasMatch(_password.text);
  bool get _formValid =>
      _passwordValid && _password.text == _confirmPassword.text;

  @override
  void dispose() {
    _password.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final token = widget.token;
    return Scaffold(
      key: const Key('reset_password_scaffold'),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: token == null || token.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        key: const Key('reset_password_missing_token'),
                        'Ce lien de réinitialisation est invalide.',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 16),
                      TextButton(
                        onPressed: () => context.go('/forgot-password'),
                        child:
                            const Text('Demander un nouveau lien'),
                      ),
                    ],
                  ),
                )
              : BlocConsumer<ResetPasswordCubit, ResetPasswordState>(
                  listener: (context, state) {
                    if (state is ResetPasswordSuccess) {
                      context.go('/login');
                    }
                  },
                  builder: (context, state) {
                    final loading = state is ResetPasswordLoading;
                    return SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text('Réinitialiser le mot de passe',
                              style:
                                  Theme.of(context).textTheme.headlineMedium),
                          const SizedBox(height: 24),
                          NubiaTextField(
                            controller: _password,
                            label: 'Nouveau mot de passe',
                            hint: '8 caractères minimum, dont 1 chiffre',
                            variant: NubiaTextFieldVariant.password,
                            onChanged: (_) => setState(() {}),
                          ),
                          const SizedBox(height: 12),
                          NubiaTextField(
                            controller: _confirmPassword,
                            label: 'Confirmer le mot de passe',
                            variant: NubiaTextFieldVariant.password,
                            onChanged: (_) => setState(() {}),
                          ),
                          if (state is ResetPasswordFailure) ...[
                            const SizedBox(height: 12),
                            Text(state.message,
                                style: TextStyle(
                                    color:
                                        Theme.of(context).colorScheme.error)),
                          ],
                          const SizedBox(height: 24),
                          NubiaButton(
                            key: const Key('reset_password_submit'),
                            label: 'Réinitialiser',
                            isLoading: loading,
                            onPressed: (!_formValid || loading)
                                ? null
                                : () => context
                                    .read<ResetPasswordCubit>()
                                    .submit(
                                      token: token,
                                      newPassword: _password.text,
                                    ),
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

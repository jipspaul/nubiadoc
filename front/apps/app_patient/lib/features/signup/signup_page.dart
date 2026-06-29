import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

import 'signup_cubit.dart';

class SignupPage extends StatefulWidget {
  const SignupPage({super.key});

  @override
  State<SignupPage> createState() => _SignupPageState();
}

class _SignupPageState extends State<SignupPage> {
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
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: BlocBuilder<SignupCubit, SignupState>(
            builder: (context, state) {
              final loading = state is SignupLoading;
              return SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Nubia',
                        style: Theme.of(context).textTheme.headlineMedium),
                    const SizedBox(height: 4),
                    Text('Créer un compte',
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
                    if (state is SignupFailure) ...[
                      const SizedBox(height: 12),
                      Text(
                        state.message,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error),
                      ),
                    ],
                    const SizedBox(height: 24),
                    NubiaButton(
                      label: 'Créer mon compte',
                      isLoading: loading,
                      onPressed: loading
                          ? null
                          : () => context.read<SignupCubit>().register(
                                _email.text.trim(),
                                _password.text,
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

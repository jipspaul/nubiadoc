import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_patient/presentation/features/auth/bloc/auth_bloc.dart';
import 'package:nubia_patient/presentation/features/auth/bloc/auth_event.dart';
import 'package:nubia_patient/presentation/features/auth/bloc/auth_state.dart';
import 'package:nubia_patient/presentation/widgets/nubia_button.dart';
import 'package:nubia_patient/presentation/widgets/nubia_text_field.dart';

class LoginForm extends StatefulWidget {
  const LoginForm({super.key});

  @override
  State<LoginForm> createState() => _LoginFormState();
}

class _LoginFormState extends State<LoginForm> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  String? _emailError;

  bool get _canSubmit =>
      _emailController.text.isNotEmpty && _passwordController.text.isNotEmpty;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _submit() {
    final email = _emailController.text.trim();
    final emailRegex = RegExp(r'^[^@]+@[^@]+\.[^@]+$');
    if (!emailRegex.hasMatch(email)) {
      setState(() => _emailError = 'Adresse e-mail invalide.');
      return;
    }
    setState(() => _emailError = null);
    context.read<AuthBloc>().add(
          AuthLoginRequested(
            email: email,
            password: _passwordController.text,
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<AuthBloc, AuthState>(
      listener: (context, state) {
        if (state is AuthFailure) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.message),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }
      },
      builder: (context, state) {
        final isLoading = state is AuthLoading;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            NubiaTextField(
              key: const Key('login_email_field'),
              controller: _emailController,
              label: 'Adresse e-mail',
              hint: 'exemple@cabinet.fr',
              errorText: _emailError,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),
            NubiaTextField(
              key: const Key('login_password_field'),
              variant: NubiaTextFieldVariant.password,
              controller: _passwordController,
              label: 'Mot de passe',
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 32),
            NubiaButton(
              key: const Key('login_submit_button'),
              label: 'Connexion',
              onPressed: _canSubmit && !isLoading ? _submit : null,
              isLoading: isLoading,
            ),
          ],
        );
      },
    );
  }
}

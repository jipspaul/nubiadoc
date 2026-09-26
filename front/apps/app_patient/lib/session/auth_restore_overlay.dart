import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

import 'auth_cubit.dart';

/// #6981 : affiché par-dessus la route active quelle qu'elle soit — pas
/// seulement `/splash` (#6750) — pour qu'une coupure réseau pendant
/// `AuthCubit.restore()` propose « Réessayer » au lieu de laisser la route
/// demandée (ex. un deep link `/mes-rdv`, qui ne construit jamais `/splash`)
/// se rabattre sur le login alors que la session est encore valide.
class AuthRestoreOverlay extends StatelessWidget {
  const AuthRestoreOverlay({super.key, required this.child});

  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AuthCubit, AuthState>(
      builder: (context, state) => state is AuthRestoreFailed
          ? Scaffold(
              body: NubiaErrorWidget(
                message: state.message,
                onRetry: () => context.read<AuthCubit>().restore(),
              ),
            )
          : child ?? const SizedBox.shrink(),
    );
  }
}

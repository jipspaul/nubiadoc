import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'features/auth/bloc/auth_bloc.dart';
import 'features/auth/bloc/auth_event.dart';
import 'features/auth/bloc/auth_state.dart';
import 'features/auth/data/auth_repository.dart';
import 'features/auth/data/token_storage.dart';
import 'features/auth/login_screen.dart';
import 'theme/nubia_theme.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => AuthBloc(
        repository: FakeAuthRepository(),
        tokenStorage: InMemoryTokenStorage(),
      )..add(const AuthCheckRequested()),
      child: MaterialApp(
        title: 'Nubia',
        theme: NubiaTheme.light,
        darkTheme: NubiaTheme.dark,
        themeMode: ThemeMode.system,
        home: const _AuthGate(),
      ),
    );
  }
}

/// Routeur conditionnel : redirige vers [LoginScreen] ou [MyHomePage] selon l'état auth.
class _AuthGate extends StatelessWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AuthBloc, AuthState>(
      builder: (context, state) {
        if (state is AuthAuthenticated) {
          return const MyHomePage();
        }
        return const LoginScreen();
      },
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  int _counter = 0;

  void _increment() {
    setState(() {
      _counter++;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Flutter Demo'),
      ),
      body: Column(
        children: [
          const Text('Hello Flutter'),
          Text('$_counter'),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        key: const ValueKey('inc'),
        onPressed: _increment,
        child: const Icon(Icons.add),
      ),
    );
  }
}

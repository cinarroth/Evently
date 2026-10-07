import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:evently_core/evently_core.dart';

import 'screens/auth/login_screen.dart';
import 'screens/home_shell.dart';

class EventlyUserApp extends StatelessWidget {
  const EventlyUserApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Evently',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      home: const _AuthGate(),
    );
  }
}

/// Listens to auth state and shows either the login flow or the app shell.
class _AuthGate extends StatelessWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context) {
    final authRepo = AuthRepository();
    return StreamBuilder<(User?, AppUser?)>(
      stream: authRepo.userWithProfile,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: LoadingView());
        }
        final (user, _) = snapshot.data ?? (null, null);
        return user == null ? const LoginScreen() : const HomeShell();
      },
    );
  }
}

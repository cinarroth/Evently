import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:evently_core/evently_core.dart';

import 'screens/auth/admin_login_screen.dart';
import 'screens/home_shell.dart';

class EventlyAdminApp extends StatelessWidget {
  const EventlyAdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Evently Admin',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      home: const _AdminGate(),
    );
  }
}

/// Shows admin shell only when the signed-in user actually has the admin
/// role; otherwise renders a clear "not authorized" screen (the admin app is
/// useless without the role).
class _AdminGate extends StatelessWidget {
  const _AdminGate();

  @override
  Widget build(BuildContext context) {
    final authRepo = AuthRepository();
    return StreamBuilder<(User?, AppUser?)>(
      stream: authRepo.userWithProfile,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: LoadingView());
        }
        final (user, profile) = snapshot.data ?? (null, null);
        if (user == null) return const AdminLoginScreen();
        if (profile == null || !profile.isAdmin) {
          return const _NotAdminScreen();
        }
        return const AdminHomeShell();
      },
    );
  }
}

class _NotAdminScreen extends StatelessWidget {
  const _NotAdminScreen();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final authRepo = AuthRepository();
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.admin_panel_settings_outlined,
                  size: 64, color: theme.colorScheme.error),
              const SizedBox(height: 16),
              Text('Admin access required',
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text(
                'This account does not have the admin role.\nAsk an existing admin to promote you '
                'via the setAdminRole function.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: () => authRepo.signOut(),
                icon: const Icon(Icons.logout_rounded),
                label: const Text('Sign out'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

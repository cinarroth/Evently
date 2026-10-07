import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:evently_core/evently_core.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final AuthRepository _authRepo;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _authRepo = AuthRepository();
    // Register this device for push once the profile screen opens.
    FcmService(_authRepo).initialise();
  }

  Future<void> _editName(AppUser user) async {
    final ctrl = TextEditingController(text: user.displayName);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Display name'),
        content: TextField(controller: ctrl, autofocus: true, maxLength: 80),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('Save')),
        ],
      ),
    );
    if (name == null || name.isEmpty || name == user.displayName) return;
    setState(() => _busy = true);
    try {
      await _authRepo.updateProfile(displayName: name);
    } catch (e) {
      if (mounted) showErrorSnackBar(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signOut() async {
    final confirmed = await confirmDestructive(
      context,
      title: 'Sign out?',
      message: 'You will need to sign in again to see your tickets.',
      confirmLabel: 'Sign out',
    );
    if (!confirmed) return;
    await _authRepo.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: StreamBuilder<(Object?, Object?)>(
        stream: _authRepo.userWithProfile,
        builder: (context, snapshot) {
          final (fbUser, profile) = snapshot.data ?? (null, null);
          final authUser = fbUser as User?;
          final user = profile as AppUser?;
          final email = authUser?.email ?? '';

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const SizedBox(height: 8),
              CircleAvatar(
                radius: 44,
                child: Text(
                  _initials(user),
                  style: theme.textTheme.headlineMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: Text(
                  user?.displayName ?? '…',
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              if (email.isNotEmpty)
                Center(
                  child: Text(
                    email,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
              const SizedBox(height: 24),
              Card(
                margin: EdgeInsets.zero,
                child: ListTile(
                  leading: const Icon(Icons.badge_outlined),
                  title: const Text('Edit display name'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: _busy || user == null ? null : () => _editName(user),
                ),
              ),
              const SizedBox(height: 24),
              PrimaryButton(
                label: 'Sign out',
                icon: Icons.logout_rounded,
                destructive: true,
                expand: true,
                onPressed: _signOut,
              ),
            ],
          );
        },
      ),
    );
  }

  String _initials(AppUser? user) {
    final name = user?.displayName ?? '';
    if (name.isEmpty || name == 'Loading…') return '•';
    final parts = name.trim().split(RegExp(r'\s+'));
    return parts.take(2).map((p) => p[0].toUpperCase()).join();
  }
}

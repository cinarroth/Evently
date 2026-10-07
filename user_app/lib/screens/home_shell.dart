import 'package:flutter/material.dart';

import 'package:evently_core/evently_core.dart';

import 'events/browse_screen.dart';
import 'events/my_events_screen.dart';
import 'notifications/notifications_screen.dart';
import 'profile/profile_screen.dart';

/// Bottom-nav shell for the user app: browse, my events, notifications and
/// profile. Admins get a different shell in the admin app.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: const [
          BrowseScreen(),
          MyEventsScreen(),
          NotificationsScreen(),
          ProfileScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.explore_outlined),
            selectedIcon: Icon(Icons.explore_rounded),
            label: 'Discover',
          ),
          const NavigationDestination(
            icon: Icon(Icons.event_available_outlined),
            selectedIcon: Icon(Icons.event_available_rounded),
            label: 'My events',
          ),
          const _NotificationsTab(),
          const NavigationDestination(
            icon: Icon(Icons.person_outline_rounded),
            selectedIcon: Icon(Icons.person_rounded),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}

/// Badge dot on the notifications tab when unread items exist.
class _NotificationsTab extends StatelessWidget {
  const _NotificationsTab();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: NotificationsRepository().watchUnreadCount(),
      builder: (context, snapshot) {
        final unread = snapshot.data ?? 0;
        return NavigationDestination(
          icon: Badge(
            isLabelVisible: unread > 0,
            label: Text('$unread'),
            child: const Icon(Icons.notifications_none_rounded),
          ),
          selectedIcon: Badge(
            isLabelVisible: unread > 0,
            label: Text('$unread'),
            child: const Icon(Icons.notifications_rounded),
          ),
          label: 'Alerts',
        );
      },
    );
  }
}

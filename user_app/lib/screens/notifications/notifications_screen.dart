import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:evently_core/evently_core.dart';

/// In-app inbox mirroring the push notifications the user receives.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  late final NotificationsRepository _repo;
  bool _marking = false;

  @override
  void initState() {
    super.initState();
    _repo = NotificationsRepository();
  }

  Future<void> _markAll(List<NotificationItem> items) async {
    if (_marking) return;
    final unread = items.where((n) => !n.read).map((n) => n.id).toList();
    if (unread.isEmpty) return;
    setState(() => _marking = true);
    try {
      await _repo.markRead(unread);
    } catch (e) {
      if (mounted) showErrorSnackBar(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _marking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Alerts'),
        actions: [
          StreamBuilder<List<NotificationItem>>(
            stream: _repo.watchInbox(),
            builder: (context, snapshot) {
              final items = snapshot.data ?? const <NotificationItem>[];
              final hasUnread = items.any((n) => !n.read);
              return TextButton(
                onPressed: hasUnread ? () => _markAll(items) : null,
                child: _marking
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Mark all read'),
              );
            },
          ),
        ],
      ),
      body: StreamBuilder<List<NotificationItem>>(
        stream: _repo.watchInbox(),
        builder: (context, snapshot) {
          return StreamStateView<List<NotificationItem>>(
            snapshot: snapshot,
            onRefresh: () async {},
            emptyIcon: Icons.notifications_none_rounded,
            emptyTitle: 'No notifications',
            emptyMessage: 'Reminders and event updates will appear here.',
            builder: (context, items) => ListView.separated(
              padding: const EdgeInsets.only(bottom: 24, top: 4),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 2),
              itemBuilder: (context, i) => _NotificationTile(item: items[i]),
            ),
          );
        },
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.item});

  final NotificationItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final time = item.createdAt;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      color: item.read
          ? null
          : theme.colorScheme.primaryContainer.withValues(alpha: 0.35),
      child: ListTile(
        leading: Icon(_iconFor(item.type), color: theme.colorScheme.primary),
        title: Text(
          item.title,
          style:
              theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 2),
            Text(item.body, style: theme.textTheme.bodySmall),
            if (time != null) ...[
              const SizedBox(height: 4),
              Text(
                DateFormat('MMM d, HH:mm').format(time.toLocal()),
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
            ],
          ],
        ),
        isThreeLine: true,
      ),
    );
  }

  IconData _iconFor(String type) {
    switch (type) {
      case 'registration_created':
        return Icons.how_to_reg_rounded;
      case 'registration_canceled':
      case 'registration_removed':
        return Icons.event_busy_rounded;
      case 'event_reminder':
        return Icons.alarm_rounded;
      case 'event_updated':
        return Icons.edit_note_rounded;
      case 'event_canceled':
      case 'event_status':
        return Icons.event_busy_rounded;
      case 'checked_in':
        return Icons.verified_rounded;
      case 'announcement':
        return Icons.campaign_rounded;
      default:
        return Icons.notifications_rounded;
    }
  }
}

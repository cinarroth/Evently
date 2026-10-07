import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:evently_core/evently_core.dart';

import 'event_editor_screen.dart';
import 'event_participants_screen.dart';

/// All events with status filter; entry point to creation and management.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late final EventRepository _eventRepo;
  String _statusFilter = 'all';

  @override
  void initState() {
    super.initState();
    _eventRepo = EventRepository();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Events'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_rounded),
            tooltip: 'New event',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                  builder: (_) => const EventEditorScreen()),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'all', label: Text('All')),
                ButtonSegment(value: 'upcoming', label: Text('Upcoming')),
                ButtonSegment(value: 'past', label: Text('Past')),
                ButtonSegment(value: 'canceled', label: Text('Canceled')),
              ],
              selected: {_statusFilter},
              onSelectionChanged: (s) =>
                  setState(() => _statusFilter = s.first),
            ),
          ),
          Expanded(
            child: StreamBuilder<List<Event>>(
              stream: _eventRepo.watchAll(),
              builder: (context, snapshot) {
                return StreamStateView<List<Event>>(
                  snapshot: snapshot,
                  onRefresh: () async {},
                  emptyIcon: Icons.event_busy_outlined,
                  emptyTitle: 'No events yet',
                  emptyMessage: 'Tap + to create the first event.',
                  builder: (context, events) {
                    final filtered = events.where((e) {
                      switch (_statusFilter) {
                        case 'upcoming':
                          return e.status == EventStatus.upcoming ||
                              e.status == EventStatus.ongoing;
                        case 'past':
                          return e.status == EventStatus.completed;
                        case 'canceled':
                          return e.status == EventStatus.canceled;
                        default:
                          return true;
                      }
                    }).toList();
                    if (filtered.isEmpty) {
                      return EmptyState(
                        icon: Icons.filter_alt_off_outlined,
                        title: 'Nothing in this view',
                        message: 'Try a different filter.',
                      );
                    }
                    return ListView.builder(
                      padding: const EdgeInsets.only(bottom: 24),
                      itemCount: filtered.length,
                      itemBuilder: (context, i) => _AdminEventTile(
                        event: filtered[i],
                        onOpen: () => Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) => EventParticipantsScreen(
                                eventId: filtered[i].id),
                          ),
                        ),
                        onEdit: () => Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) =>
                                EventEditorScreen(existing: filtered[i]),
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _AdminEventTile extends StatelessWidget {
  const _AdminEventTile(
      {required this.event, required this.onOpen, required this.onEdit});

  final Event event;
  final VoidCallback onOpen;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateFmt = DateFormat('MMM d, yyyy · HH:mm');
    final capacityPct = event.capacity > 0
        ? ((event.participantsCount / event.capacity) * 100).round()
        : 0;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        onTap: onOpen,
        title: Row(
          children: [
            Expanded(
              child: Text(
                event.title,
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            StatusChip(status: event.status),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              '${dateFmt.format(event.startAt.toLocal())}  ·  ${event.location}',
              style: theme.textTheme.bodySmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.group_rounded,
                    size: 14, color: theme.colorScheme.outline),
                const SizedBox(width: 4),
                Text(
                  '${event.participantsCount} / ${event.capacity} ($capacityPct%)'
                  '  ·  ${event.checkedInCount} checked in',
                  style: theme.textTheme.labelMedium,
                ),
              ],
            ),
          ],
        ),
        trailing: PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert_rounded),
          onSelected: (value) {
            if (value == 'edit') onEdit();
          },
          itemBuilder: (ctx) => [
            const PopupMenuItem(value: 'edit', child: Text('Edit event')),
          ],
        ),
      ),
    );
  }
}

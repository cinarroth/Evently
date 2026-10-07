import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:evently_core/evently_core.dart';

/// Single-event management: details, participant list with check-in state,
/// remove participants, status controls, reminder + delete actions.
class EventParticipantsScreen extends StatefulWidget {
  const EventParticipantsScreen({super.key, required this.eventId});

  final String eventId;

  @override
  State<EventParticipantsScreen> createState() =>
      _EventParticipantsScreenState();
}

class _EventParticipantsScreenState extends State<EventParticipantsScreen> {
  late final EventRepository _eventRepo;
  late final RegistrationRepository _regRepo;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _eventRepo = EventRepository();
    _regRepo = RegistrationRepository();
  }

  Future<void> _setStatus(Event event, EventStatus status) async {
    if (_busy) return;
    if (status == EventStatus.canceled) {
      final confirmed = await confirmDestructive(
        context,
        title: 'Cancel event?',
        message:
            'All registered participants will be notified. This cannot be undone.',
        confirmLabel: 'Cancel event',
      );
      if (!confirmed) return;
    }
    setState(() => _busy = true);
    try {
      await _eventRepo.setEventStatus(event.id, status);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Status set to ${status.wire}')),
        );
      }
    } catch (e) {
      if (mounted) showErrorSnackBar(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendReminder(Event event) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _eventRepo.sendReminder(event.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Reminder sent to all participants')),
        );
      }
    } catch (e) {
      if (mounted) showErrorSnackBar(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(Event event) async {
    final confirmed = await confirmDestructive(
      context,
      title: 'Delete event?',
      message:
          '"${event.title}" and all its registrations will be permanently deleted.',
      confirmLabel: 'Delete',
    );
    if (!confirmed) return;
    setState(() => _busy = true);
    try {
      await _eventRepo.deleteEvent(event.id);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) showErrorSnackBar(context, friendlyError(e));
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _removeParticipant(Event event, String userId) async {
    final confirmed = await confirmDestructive(
      context,
      title: 'Remove participant?',
      message: 'Their spot will be freed and they will be notified.',
      confirmLabel: 'Remove',
    );
    if (!confirmed) return;
    try {
      await _regRepo.removeParticipant(event.id, userId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Participant removed')),
        );
      }
    } catch (e) {
      if (mounted) showErrorSnackBar(context, friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Manage event')),
      body: StreamBuilder<Event>(
        stream: _eventRepo.watchEvent(widget.eventId),
        builder: (context, eventSnap) {
          if (eventSnap.hasError) {
            return ErrorState(
                message: '${eventSnap.error}', onRetry: () => setState(() {}));
          }
          if (!eventSnap.hasData) return const LoadingView();
          final event = eventSnap.data!;

          return Column(
            children: [
              _Header(event: event),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    PopupMenuButton<EventStatus>(
                      tooltip: 'Set status',
                      onSelected: (s) => _setStatus(event, s),
                      itemBuilder: (ctx) => EventStatus.values
                          .map((s) =>
                              PopupMenuItem(value: s, child: Text(s.wire)))
                          .toList(),
                      child: OutlinedButton.icon(
                        onPressed: null,
                        icon: const Icon(Icons.published_with_changes_rounded,
                            size: 18),
                        label: const Text('Status'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: _busy || event.status != EventStatus.upcoming
                          ? null
                          : () => _sendReminder(event),
                      icon: const Icon(Icons.notifications_active_outlined,
                          size: 18),
                      label: const Text('Remind all'),
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: 'Delete event',
                      icon: Icon(Icons.delete_outline_rounded,
                          color: theme.colorScheme.error),
                      onPressed: _busy ? null : () => _delete(event),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: StreamBuilder<List<Registration>>(
                  stream: _regRepo.watchParticipants(event.id),
                  builder: (context, regsSnap) {
                    return StreamStateView<List<Registration>>(
                      snapshot: regsSnap,
                      emptyIcon: Icons.group_off_outlined,
                      emptyTitle: 'No participants yet',
                      emptyMessage: 'Registrations will appear here.',
                      builder: (context, regs) {
                        return StreamBuilder<Map<String, DateTime?>>(
                          stream: _regRepo.watchCheckins(event.id),
                          builder: (context, checkinSnap) {
                            final checkins =
                                checkinSnap.data ?? const <String, DateTime?>{};
                            return ListView.separated(
                              itemCount: regs.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 2),
                              padding: const EdgeInsets.only(bottom: 24),
                              itemBuilder: (context, i) {
                                final reg = regs[i];
                                final checkedIn =
                                    checkins[reg.userId] != null ||
                                        reg.checkedIn;
                                return ListTile(
                                  leading: CircleAvatar(
                                    child: Text(reg.userId
                                        .substring(0, 1)
                                        .toUpperCase()),
                                  ),
                                  title: Text(
                                    reg.userId,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodyMedium,
                                  ),
                                  subtitle: reg.registeredAt != null
                                      ? Text(DateFormat('MMM d · HH:mm')
                                          .format(reg.registeredAt!.toLocal()))
                                      : null,
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (checkedIn)
                                        Icon(Icons.verified_rounded,
                                            color: AppTheme.success, size: 20)
                                      else
                                        Text('—',
                                            style: theme.textTheme.bodySmall),
                                      IconButton(
                                        tooltip: 'Remove participant',
                                        icon: Icon(Icons.person_remove_outlined,
                                            size: 20,
                                            color: theme.colorScheme.error),
                                        onPressed: () => _removeParticipant(
                                            event, reg.userId),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            );
                          },
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.event});

  final Event event;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateFmt = DateFormat('EEEE, MMM d yyyy · HH:mm');
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  event.title,
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              StatusChip(status: event.status),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            dateFmt.format(event.startAt.toLocal()),
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _Stat(label: 'Registered', value: '${event.participantsCount}'),
              const SizedBox(width: 24),
              _Stat(label: 'Capacity', value: '${event.capacity}'),
              const SizedBox(width: 24),
              _Stat(label: 'Checked in', value: '${event.checkedInCount}'),
              const SizedBox(width: 24),
              _Stat(label: 'Open spots', value: '${event.spotsAvailable}'),
            ],
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value,
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w800)),
        Text(label,
            style: theme.textTheme.labelSmall
                ?.copyWith(color: theme.colorScheme.outline)),
      ],
    );
  }
}

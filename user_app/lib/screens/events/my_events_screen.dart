import 'package:flutter/material.dart';

import 'package:evently_core/evently_core.dart';

import 'event_details_screen.dart';
import 'ticket_screen.dart';

/// Registrations of the signed-in user, split into upcoming + past.
class MyEventsScreen extends StatelessWidget {
  const MyEventsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final regRepo = RegistrationRepository();
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('My events'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Upcoming'),
              Tab(text: 'Past'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _RegistrationList(regRepo: regRepo, past: false),
            _RegistrationList(regRepo: regRepo, past: true),
          ],
        ),
      ),
    );
  }
}

class _RegistrationList extends StatelessWidget {
  const _RegistrationList({required this.regRepo, required this.past});

  final RegistrationRepository regRepo;
  final bool past;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<RegistrationWithEvent>>(
      stream: regRepo.watchMyRegistrations(past: past),
      builder: (context, snapshot) {
        return StreamStateView<List<RegistrationWithEvent>>(
          snapshot: snapshot,
          onRefresh: () async {},
          emptyIcon:
              past ? Icons.history_rounded : Icons.event_available_outlined,
          emptyTitle: past ? 'No past events yet' : 'No registrations yet',
          emptyMessage: past
              ? 'Events you attended will appear here.'
              : 'Browse the Discover tab and grab a spot!',
          builder: (context, pairs) => ListView.builder(
            padding: const EdgeInsets.only(bottom: 24, top: 4),
            itemCount: pairs.length,
            itemBuilder: (context, i) {
              final pair = pairs[i];
              return EventCard(
                event: pair.event,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => EventDetailsScreen(eventId: pair.event.id),
                  ),
                ),
                trailing: pair.registration.checkedIn
                    ? const _CheckedInBanner()
                    : (past ? null : _TicketAction(eventId: pair.event.id)),
              );
            },
          ),
        );
      },
    );
  }
}

class _CheckedInBanner extends StatelessWidget {
  const _CheckedInBanner();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      color: AppTheme.success.withValues(alpha: 0.12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.verified_rounded, size: 16, color: AppTheme.success),
          const SizedBox(width: 6),
          Text(
            'Checked in',
            style: theme.textTheme.labelMedium?.copyWith(
              color: AppTheme.success,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _TicketAction extends StatelessWidget {
  const _TicketAction({required this.eventId});

  final String eventId;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: OutlinedButton.icon(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute<void>(
              builder: (_) => TicketScreen(eventId: eventId)),
        ),
        icon: const Icon(Icons.qr_code_2_rounded, size: 18),
        label: const Text('Show ticket'),
      ),
    );
  }
}

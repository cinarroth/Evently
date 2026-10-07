import 'package:flutter/material.dart';

import 'package:evently_core/evently_core.dart';

import 'event_details_screen.dart';

/// Completed + canceled events, most recent first.
class PastEventsScreen extends StatefulWidget {
  const PastEventsScreen({super.key});

  @override
  State<PastEventsScreen> createState() => _PastEventsScreenState();
}

class _PastEventsScreenState extends State<PastEventsScreen> {
  late final EventRepository _eventRepo;

  @override
  void initState() {
    super.initState();
    _eventRepo = EventRepository();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Past events')),
      body: StreamBuilder<List<Event>>(
        stream: _eventRepo.watchPast(),
        builder: (context, snapshot) {
          return StreamStateView<List<Event>>(
            snapshot: snapshot,
            onRefresh: () async {},
            emptyIcon: Icons.history_rounded,
            emptyTitle: 'Nothing here yet',
            emptyMessage: 'Past events will show up here once they finish.',
            builder: (context, events) => ListView.builder(
              padding: const EdgeInsets.only(bottom: 24, top: 4),
              itemCount: events.length,
              itemBuilder: (context, i) => EventCard(
                event: events[i],
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => EventDetailsScreen(eventId: events[i].id),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

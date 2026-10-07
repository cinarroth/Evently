import 'package:flutter/material.dart';

import 'package:evently_core/evently_core.dart';

import '../../widgets/search_bar.dart';
import 'event_details_screen.dart';
import 'past_events_screen.dart';

/// Main catalog: upcoming events with search + category filter chips.
class BrowseScreen extends StatefulWidget {
  const BrowseScreen({super.key});

  @override
  State<BrowseScreen> createState() => _BrowseScreenState();
}

class _BrowseScreenState extends State<BrowseScreen> {
  final _eventRepo = EventRepository();
  String _category = 'all';
  String _query = '';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Discover'),
        actions: [
          IconButton(
            tooltip: 'Past events',
            icon: const Icon(Icons.history_rounded),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(builder: (_) => const PastEventsScreen()),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: EventSearchBar(
              onQueryChanged: (q) => setState(() => _query = q),
            ),
          ),
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                _CategoryChip(
                  label: 'All',
                  selected: _category == 'all',
                  onTap: () => setState(() => _category = 'all'),
                ),
                for (final c in eventCategories)
                  _CategoryChip(
                    label: _categoryLabel(c),
                    selected: _category == c,
                    onTap: () => setState(() => _category = c),
                  ),
              ],
            ),
          ),
          Expanded(
            child: _query.isNotEmpty
                ? _SearchResults(query: _query, onOpen: _openDetails)
                : StreamBuilder<List<Event>>(
                    stream: _eventRepo.watchUpcoming(category: _category),
                    builder: (context, snapshot) {
                      return StreamStateView<List<Event>>(
                        snapshot: snapshot,
                        onRefresh: () async {},
                        emptyIcon: Icons.celebration_outlined,
                        emptyTitle: 'No upcoming events',
                        emptyMessage: 'Check back soon — new events land here.',
                        builder: (context, events) => ListView.builder(
                          padding: const EdgeInsets.only(bottom: 24, top: 4),
                          itemCount: events.length,
                          itemBuilder: (context, i) => EventCard(
                            event: events[i],
                            onTap: () => _openDetails(events[i].id),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  void _openDetails(String eventId) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
          builder: (_) => EventDetailsScreen(eventId: eventId)),
    );
  }

  String _categoryLabel(String c) => c[0].toUpperCase() + c.substring(1);
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip(
      {required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
        labelStyle: TextStyle(
          color: selected
              ? theme.colorScheme.onPrimary
              : theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
        selectedColor: theme.colorScheme.primary,
        backgroundColor: theme.colorScheme.surfaceContainerHighest,
        side: BorderSide.none,
      ),
    );
  }
}

class _SearchResults extends StatefulWidget {
  const _SearchResults({required this.query, required this.onOpen});

  final String query;
  final void Function(String) onOpen;

  @override
  State<_SearchResults> createState() => _SearchResultsState();
}

class _SearchResultsState extends State<_SearchResults> {
  final _eventRepo = EventRepository();
  late Future<List<Event>> _future;

  @override
  void initState() {
    super.initState();
    _future = _eventRepo.search(widget.query);
  }

  @override
  void didUpdateWidget(covariant _SearchResults oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.query != widget.query) {
      _future = _eventRepo.search(widget.query);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Event>>(
      future: _future,
      builder: (context, snapshot) {
        return StreamStateView<List<Event>>(
          snapshot: snapshot,
          emptyIcon: Icons.search_off_rounded,
          emptyTitle: 'No matches',
          emptyMessage: 'Try a different keyword.',
          builder: (context, events) => ListView.builder(
            padding: const EdgeInsets.only(bottom: 24, top: 4),
            itemCount: events.length,
            itemBuilder: (context, i) => EventCard(
              event: events[i],
              onTap: () => widget.onOpen(events[i].id),
            ),
          ),
        );
      },
    );
  }
}

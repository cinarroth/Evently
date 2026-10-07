import 'package:flutter/material.dart';

import '../models/event_status.dart';
import '../theme/app_theme.dart';

/// Small colored label for the event lifecycle status.
class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.status});

  final EventStatus status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = AppTheme.statusColor(_like(status), scheme);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        _label(status),
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
        ),
      ),
    );
  }

  EventStatusLike _like(EventStatus status) {
    switch (status) {
      case EventStatus.upcoming:
        return EventStatusLike.upcoming;
      case EventStatus.ongoing:
        return EventStatusLike.ongoing;
      case EventStatus.completed:
        return EventStatusLike.completed;
      case EventStatus.canceled:
        return EventStatusLike.canceled;
    }
  }

  String _label(EventStatus status) {
    switch (status) {
      case EventStatus.upcoming:
        return 'UPCOMING';
      case EventStatus.ongoing:
        return 'ONGOING';
      case EventStatus.completed:
        return 'COMPLETED';
      case EventStatus.canceled:
        return 'CANCELED';
    }
  }
}

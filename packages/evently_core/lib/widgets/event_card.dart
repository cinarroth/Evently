import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/event.dart';
import 'participants_badge.dart';
import 'status_chip.dart';

/// Catalog card for an event: cover image, status chip, capacity bar.
class EventCard extends StatelessWidget {
  const EventCard({super.key, required this.event, this.onTap, this.trailing});

  final Event event;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateFmt = DateFormat('EEE, MMM d · HH:mm');

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Stack(
              children: [
                SizedBox(
                  height: 132,
                  width: double.infinity,
                  child: event.coverImageUrl != null
                      ? CachedNetworkImage(
                          imageUrl: event.coverImageUrl!,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => Container(
                              color: theme.colorScheme.surfaceContainerHighest),
                          errorWidget: (_, __, ___) => _CoverFallback(
                              color: theme.colorScheme.surfaceContainerHighest),
                        )
                      : _CoverFallback(
                          color: theme.colorScheme.surfaceContainerHighest),
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: StatusChip(status: event.status),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    event.title,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(Icons.event_rounded,
                          size: 15, color: theme.colorScheme.outline),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          dateFmt.format(event.startAt.toLocal()),
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.place_rounded,
                          size: 15, color: theme.colorScheme.outline),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          event.location,
                          style: theme.textTheme.bodySmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ParticipantsBadge(
                    registered: event.participantsCount,
                    capacity: event.capacity,
                  ),
                ],
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}

class _CoverFallback extends StatelessWidget {
  const _CoverFallback({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: color,
      alignment: Alignment.center,
      child: Icon(Icons.image_outlined,
          size: 40, color: Theme.of(context).colorScheme.outline),
    );
  }
}

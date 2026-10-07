import 'package:flutter/material.dart';

/// Linear capacity indicator: "n / m spots" with progress bar.
class ParticipantsBadge extends StatelessWidget {
  const ParticipantsBadge(
      {super.key, required this.registered, required this.capacity});

  final int registered;
  final int capacity;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final remaining = capacity - registered;
    final ratio = capacity > 0 ? (registered / capacity).clamp(0.0, 1.0) : 0.0;
    final full = remaining <= 0;

    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 6,
              backgroundColor: scheme.surfaceContainerHighest,
              valueColor:
                  AlwaysStoppedAnimation(full ? scheme.error : scheme.primary),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          full ? 'Full' : '$remaining / $capacity left',
          style: theme.textTheme.labelSmall?.copyWith(
            color: full ? scheme.error : scheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

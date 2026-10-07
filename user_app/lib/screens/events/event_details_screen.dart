import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:evently_core/evently_core.dart';

import 'ticket_screen.dart';

class EventDetailsScreen extends StatefulWidget {
  const EventDetailsScreen({super.key, required this.eventId});

  final String eventId;

  @override
  State<EventDetailsScreen> createState() => _EventDetailsScreenState();
}

class _EventDetailsScreenState extends State<EventDetailsScreen> {
  late final EventRepository _eventRepo;
  late final RegistrationRepository _regRepo;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _eventRepo = EventRepository();
    _regRepo = RegistrationRepository();
  }

  Future<void> _toggleRegistration(Event event, bool registered) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (registered) {
        final confirmed = await confirmDestructive(
          context,
          title: 'Cancel registration?',
          message:
              'Your spot for "${event.title}" will be freed up for others.',
          confirmLabel: 'Cancel registration',
        );
        if (!confirmed) return;
        await _regRepo.cancel(event.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Registration canceled')),
          );
        }
      } else {
        await _regRepo.register(event.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'You are registered! Find your ticket under “My events”.'),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) showErrorSnackBar(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateFmt = DateFormat('EEEE, MMMM d, yyyy · HH:mm');
    final eventStream = _eventRepo.watchEvent(widget.eventId);
    final registeredStream = _regRepo.watchIsRegistered(widget.eventId);

    return Scaffold(
      body: StreamBuilder<Event>(
        stream: eventStream,
        builder: (context, eventSnap) {
          if (eventSnap.hasError) {
            return ErrorState(
                message: '${eventSnap.error}', onRetry: () => setState(() {}));
          }
          if (!eventSnap.hasData) return const LoadingView();
          final event = eventSnap.data!;
          return StreamBuilder<bool>(
            stream: registeredStream,
            builder: (context, regSnap) {
              return CustomScrollView(
                slivers: [
                  SliverAppBar(
                    expandedHeight: 220,
                    pinned: true,
                    flexibleSpace: FlexibleSpaceBar(
                      background: event.coverImageUrl != null
                          ? CachedNetworkImage(
                              imageUrl: event.coverImageUrl!,
                              fit: BoxFit.cover,
                              placeholder: (_, __) => Container(
                                  color: theme
                                      .colorScheme.surfaceContainerHighest),
                              errorWidget: (_, __, ___) => Container(
                                  color: theme
                                      .colorScheme.surfaceContainerHighest),
                            )
                          : Container(
                              color: theme.colorScheme.surfaceContainerHighest,
                              child: Icon(Icons.image_outlined,
                                  size: 56, color: theme.colorScheme.outline),
                            ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              StatusChip(status: event.status),
                              const SizedBox(width: 8),
                              if (event.category != 'general')
                                Chip(
                                  label: Text(event.category),
                                  visualDensity: VisualDensity.compact,
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            event.title,
                            style: theme.textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.5),
                          ),
                          const SizedBox(height: 16),
                          _InfoRow(
                            icon: Icons.event_rounded,
                            label: dateFmt.format(event.startAt.toLocal()),
                          ),
                          if (event.endAt != null)
                            _InfoRow(
                              icon: Icons.timer_outlined,
                              label:
                                  'Until ${DateFormat('HH:mm').format(event.endAt!.toLocal())}',
                            ),
                          _InfoRow(
                              icon: Icons.place_rounded, label: event.location),
                          const SizedBox(height: 16),
                          ParticipantsBadge(
                            registered: event.participantsCount,
                            capacity: event.capacity,
                          ),
                          const SizedBox(height: 24),
                          Text('About this event',
                              style: theme.textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 8),
                          SelectableText(
                            event.description,
                            style: theme.textTheme.bodyMedium
                                ?.copyWith(height: 1.5),
                          ),
                          const SizedBox(height: 110),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
      // Bottom action bar driven by the same streams (event + registration).
      bottomNavigationBar: StreamBuilder<Event>(
        stream: eventStream,
        builder: (context, eventSnap) {
          final event = eventSnap.data;
          if (event == null) return const SizedBox(height: 70);

          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: StreamBuilder<bool>(
                stream: registeredStream,
                builder: (context, regSnap) {
                  final registered = regSnap.data ?? false;

                  if (event.isPast) {
                    return const SizedBox.shrink();
                  }
                  if (event.status == EventStatus.canceled) {
                    return _BannedBar(text: 'This event was canceled');
                  }
                  if (registered) {
                    return Row(
                      children: [
                        Expanded(
                          child: PrimaryButton(
                            label: 'View ticket',
                            icon: Icons.qr_code_2_rounded,
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute<void>(
                                builder: (_) =>
                                    TicketScreen(eventId: widget.eventId),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: PrimaryButton(
                            label: 'Cancel spot',
                            icon: Icons.event_busy_rounded,
                            destructive: true,
                            busy: _busy,
                            onPressed: () => _toggleRegistration(event, true),
                          ),
                        ),
                      ],
                    );
                  }
                  final full = event.isFull;
                  final closedForReg = event.status == EventStatus.completed ||
                      event.participantsCount >= event.capacity;
                  return PrimaryButton(
                    label: full
                        ? 'Event is full'
                        : closedForReg
                            ? 'Registration closed'
                            : 'Register now',
                    icon: full || closedForReg
                        ? Icons.do_not_disturb_on_rounded
                        : Icons.how_to_reg_rounded,
                    expand: true,
                    busy: _busy,
                    onPressed: (full || closedForReg)
                        ? null
                        : () => _toggleRegistration(event, false),
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }
}

class _BannedBar extends StatelessWidget {
  const _BannedBar({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          text,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.onErrorContainer,
              ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

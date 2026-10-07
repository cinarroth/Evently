import 'package:flutter/material.dart';

import 'package:evently_core/evently_core.dart';

/// Admin broadcasts: app-wide announcements + targeted event updates.
class AnnouncementsScreen extends StatefulWidget {
  const AnnouncementsScreen({super.key});

  @override
  State<AnnouncementsScreen> createState() => _AnnouncementsScreenState();
}

class _AnnouncementsScreenState extends State<AnnouncementsScreen> {
  late final EventRepository _eventRepo;
  final _titleCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _eventRepo = EventRepository();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  Future<void> _sendAnnouncement() async {
    if (_busy) return;
    final title = _titleCtrl.text.trim();
    final body = _bodyCtrl.text.trim();
    if (title.length < 3 || body.length < 3) {
      showErrorSnackBar(
          context, 'Title and message must be at least 3 characters.');
      return;
    }
    final confirmed = await confirmDestructive(
      context,
      title: 'Send announcement?',
      message: 'Every user with notifications enabled will receive this push.',
      confirmLabel: 'Send',
    );
    if (!confirmed) return;

    setState(() => _busy = true);
    try {
      await _eventRepo.sendAnnouncement(title, body);
      _titleCtrl.clear();
      _bodyCtrl.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Announcement sent 📣')),
        );
      }
    } catch (e) {
      if (mounted) showErrorSnackBar(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendEventUpdate() async {
    if (_busy) return;
    if (!mounted) return;

    final picked = await _pickEventForUpdate();
    if (picked == null || !mounted) return;
    final body = await _askUpdateBody(picked);
    if (body == null || body.isEmpty || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await _eventRepo.notifyEventUpdate(picked.id, body);
      messenger.showSnackBar(
        const SnackBar(content: Text('Event update sent')),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(friendlyError(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Shows the event picker (no BuildContext crosses an async gap).
  Future<_EventChoice?> _pickEventForUpdate() async {
    final events = await _eventRepo.watchUpcoming().first;
    if (events.isEmpty) {
      if (!mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No upcoming events to update.')),
      );
      return null;
    }
    if (!mounted) return null;
    return showDialog<_EventChoice>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Pick an event'),
        children: [
          for (final e in events.take(20))
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, _EventChoice(e.id, e.title)),
              child: Text(e.title),
            ),
        ],
      ),
    );
  }

  Future<String?> _askUpdateBody(_EventChoice picked) {
    final bodyCtrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Update for "${picked.title}"'),
        content: TextField(
          controller: bodyCtrl,
          autofocus: true,
          maxLength: 500,
          decoration: const InputDecoration(hintText: 'What changed?'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, bodyCtrl.text.trim()),
              child: const Text('Send')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Announcements')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('App-wide announcement',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          TextFormField(
            controller: _titleCtrl,
            decoration: const InputDecoration(labelText: 'Title'),
            maxLength: 120,
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _bodyCtrl,
            decoration: const InputDecoration(
                labelText: 'Message', alignLabelWithHint: true),
            maxLines: 4,
            maxLength: 1000,
          ),
          const SizedBox(height: 16),
          PrimaryButton(
            label: 'Send to all users',
            icon: Icons.campaign_rounded,
            busy: _busy,
            expand: true,
            onPressed: _sendAnnouncement,
          ),
          const Divider(height: 48),
          Text('Event update',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(
            'Notify registered participants of a specific event about an important change.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 12),
          PrimaryButton(
            label: 'Notify event participants',
            icon: Icons.forward_to_inbox_rounded,
            busy: _busy,
            expand: true,
            onPressed: _sendEventUpdate,
          ),
        ],
      ),
    );
  }
}

class _EventChoice {
  const _EventChoice(this.id, this.title);
  final String id;
  final String title;
}

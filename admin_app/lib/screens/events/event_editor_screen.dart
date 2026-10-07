import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import 'package:evently_core/evently_core.dart';

/// Create or edit an event. Cover image is picked locally, uploaded to
/// Storage in admin-only path `events/{eventId}/cover_<ts>.<ext>` (the rules
/// whitelist that shape), then the URL is passed to adminCreateEvent.
class EventEditorScreen extends StatefulWidget {
  const EventEditorScreen({super.key, this.existing});

  final Event? existing;

  @override
  State<EventEditorScreen> createState() => _EventEditorScreenState();
}

class _EventEditorScreenState extends State<EventEditorScreen> {
  late final EventRepository _eventRepo;
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _titleCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _locationCtrl;
  late final TextEditingController _capacityCtrl;

  DateTime? _startAt;
  DateTime? _endAt;
  String _category = 'general';
  File? _pickedImage;
  String? _existingCoverUrl;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _eventRepo = EventRepository();
    final e = widget.existing;
    _titleCtrl = TextEditingController(text: e?.title ?? '');
    _descCtrl = TextEditingController(text: e?.description ?? '');
    _locationCtrl = TextEditingController(text: e?.location ?? '');
    _capacityCtrl =
        TextEditingController(text: e == null ? '' : '${e.capacity}');
    _startAt = e?.startAt;
    _endAt = e?.endAt;
    _category = e?.category ?? 'general';
    _existingCoverUrl = e?.coverImageUrl;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _locationCtrl.dispose();
    _capacityCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate({required bool isStart}) async {
    final initial = isStart
        ? _startAt ?? DateTime.now()
        : _endAt ?? _startAt ?? DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime.now().subtract(const Duration(hours: 23)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
    );
    if (date == null) return;
    if (!mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null) return;
    final combined =
        DateTime(date.year, date.month, date.day, time.hour, time.minute);
    setState(() {
      if (isStart) {
        _startAt = combined;
      } else {
        _endAt = combined;
      }
    });
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
        source: ImageSource.gallery, maxWidth: 1920, imageQuality: 82);
    if (picked == null) return;
    setState(() => _pickedImage = File(picked.path));
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || _busy) return;
    if (_startAt == null) {
      showErrorSnackBar(context, 'Pick a start date & time.');
      return;
    }
    if (_endAt != null && _endAt!.isBefore(_startAt!)) {
      showErrorSnackBar(context, 'End time must be after the start time.');
      return;
    }

    setState(() => _busy = true);
    try {
      final existingEvent = widget.existing;
      Event draft = Event(
        id: existingEvent?.id ?? '',
        title: _titleCtrl.text.trim(),
        description: _descCtrl.text.trim(),
        coverImageUrl: _existingCoverUrl,
        location: _locationCtrl.text.trim(),
        startAt: _startAt!,
        endAt: _endAt,
        capacity: int.tryParse(_capacityCtrl.text.trim()) ?? 0,
        participantsCount: existingEvent?.participantsCount ?? 0,
        checkedInCount: existingEvent?.checkedInCount ?? 0,
        status: existingEvent?.status ?? EventStatus.upcoming,
        category: _category,
        organizerId: existingEvent?.organizerId ?? '',
        createdAt: existingEvent?.createdAt,
        updatedAt: existingEvent?.updatedAt,
      );

      if (_pickedImage != null) {
        // New event: upload needs an ID, so create a stub event first.
        final eventId = existingEvent?.id ??
            await _eventRepo.createEvent(_withCover(draft, null));
        final url = await _eventRepo.uploadCover(eventId, _pickedImage!);
        if (existingEvent == null) {
          await _eventRepo.updateEvent(
              eventId, _withCover(draft.copyWith(id: eventId), url));
          draft = _withCover(draft.copyWith(id: eventId), url);
        } else {
          draft = _withCover(draft, url);
          await _eventRepo.updateEvent(eventId, draft);
        }
      } else if (existingEvent == null) {
        await _eventRepo.createEvent(draft);
      } else {
        await _eventRepo.updateEvent(existingEvent.id, draft);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                existingEvent == null ? 'Event created 🎉' : 'Event updated'),
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) showErrorSnackBar(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Event _withCover(Event e, String? url) => Event(
        id: e.id,
        title: e.title,
        description: e.description,
        coverImageUrl: url,
        location: e.location,
        startAt: e.startAt,
        endAt: e.endAt,
        capacity: e.capacity,
        participantsCount: e.participantsCount,
        checkedInCount: e.checkedInCount,
        status: e.status,
        category: e.category,
        organizerId: e.organizerId,
        createdAt: e.createdAt,
        updatedAt: e.updatedAt,
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEdit = widget.existing != null;

    return Scaffold(
      appBar: AppBar(title: Text(isEdit ? 'Edit event' : 'New event')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            GestureDetector(
              onTap: _pickImage,
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Container(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(16),
                    image: _imageDecoration(),
                  ),
                  child: _imageProvider() == null
                      ? Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.add_photo_alternate_outlined,
                                size: 44, color: theme.colorScheme.outline),
                            const SizedBox(height: 8),
                            Text('Add cover image',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                    color: theme.colorScheme.outline)),
                          ],
                        )
                      : null,
                ),
              ),
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _titleCtrl,
              decoration: const InputDecoration(labelText: 'Title'),
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              validator: (v) {
                final value = v?.trim() ?? '';
                if (value.isEmpty) return 'Enter a title';
                if (value.length < 3) return 'Title is too short';
                if (value.length > 200) return 'Title is too long';
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _descCtrl,
              decoration: const InputDecoration(
                labelText: 'Description',
                alignLabelWithHint: true,
              ),
              maxLines: 5,
              textCapitalization: TextCapitalization.sentences,
              validator: (v) {
                final value = v?.trim() ?? '';
                if (value.isEmpty) return 'Describe the event';
                if (value.length > 5000) return 'Description is too long';
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _locationCtrl,
              decoration: const InputDecoration(
                labelText: 'Location',
                prefixIcon: Icon(Icons.place_outlined),
              ),
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              validator: (v) =>
                  (v ?? '').trim().isEmpty ? 'Enter a location' : null,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _category,
              decoration: const InputDecoration(labelText: 'Category'),
              items: eventCategories
                  .map((c) => DropdownMenuItem(
                        value: c,
                        child: Text(c[0].toUpperCase() + c.substring(1)),
                      ))
                  .toList(),
              onChanged: (v) => setState(() => _category = v ?? 'general'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _capacityCtrl,
              decoration: InputDecoration(
                labelText: 'Capacity',
                helperText: widget.existing == null
                    ? null
                    : 'Cannot be lower than the current participant count',
                prefixIcon: const Icon(Icons.groups_outlined),
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [_DigitsOnly()],
              validator: (v) {
                final n = int.tryParse(v ?? '');
                if (n == null || n < 1) return 'Capacity must be at least 1';
                if (n > 100000) return 'Capacity is too large';
                final existing = widget.existing;
                if (existing != null && n < existing.participantsCount) {
                  return 'Already ${existing.participantsCount} registered — raise the limit instead.';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            _DateField(
              label: 'Starts',
              value: _startAt,
              onTap: () => _pickDate(isStart: true),
            ),
            _DateField(
              label: 'Ends (optional)',
              value: _endAt,
              onTap: () => _pickDate(isStart: false),
            ),
            const SizedBox(height: 24),
            PrimaryButton(
              label: isEdit ? 'Save changes' : 'Create event',
              icon: isEdit ? Icons.save_rounded : Icons.add_rounded,
              busy: _busy,
              expand: true,
              onPressed: _save,
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  ImageProvider? _imageProvider() {
    if (_pickedImage != null) return FileImage(_pickedImage!);
    if (_existingCoverUrl != null) return NetworkImage(_existingCoverUrl!);
    return null;
  }

  DecorationImage? _imageDecoration() {
    final provider = _imageProvider();
    return provider == null
        ? null
        : DecorationImage(image: provider, fit: BoxFit.cover);
  }
}

class _DateField extends StatelessWidget {
  const _DateField(
      {required this.label, required this.value, required this.onTap});

  final String label;
  final DateTime? value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fmt = DateFormat('EEE, MMM d yyyy · HH:mm');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            prefixIcon: const Icon(Icons.schedule_outlined),
            errorStyle: const TextStyle(height: 0),
          ),
          child: Text(
            value == null ? 'Pick date & time' : fmt.format(value!.toLocal()),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: value == null ? theme.colorScheme.outline : null,
            ),
          ),
        ),
      ),
    );
  }
}

class _DigitsOnly extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    return RegExp(r'^\d*$').hasMatch(newValue.text) ? newValue : oldValue;
  }
}

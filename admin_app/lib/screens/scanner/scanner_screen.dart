import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'package:evently_core/evently_core.dart';

/// Check-in scanner. Pick an event, scan the participant QR, backend verifies
/// the signature + registration + duplicate state inside a transaction.
class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  late final EventRepository _eventRepo;
  late final RegistrationRepository _regRepo;
  MobileScannerController? _camera;
  String? _selectedEventId;
  String? _selectedEventTitle;
  bool _processing = false;
  bool _torchOn = false;

  @override
  void initState() {
    super.initState();
    _eventRepo = EventRepository();
    _regRepo = RegistrationRepository();
  }

  @override
  void dispose() {
    _camera?.dispose();
    super.dispose();
  }

  void _ensureCamera() {
    if (_camera == null && _selectedEventId != null) {
      _camera = MobileScannerController(detectionTimeoutMs: 1200);
    }
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_processing || _selectedEventId == null) return;
    final code = capture.barcodes.firstOrNull?.rawValue;
    if (code == null || code.isEmpty) return;

    setState(() => _processing = true);
    await _checkIn(code);
    if (mounted) setState(() => _processing = false);
  }

  Future<void> _checkIn(String qrPayload) async {
    try {
      final res = await _regRepo.checkIn(_selectedEventId!, qrPayload);
      if (!mounted) return;
      final userId = (res['userId'] ?? '').toString();
      final short = userId.length > 8 ? userId.substring(0, 8) : userId;
      _showResult(
        success: true,
        title: 'Checked in',
        message: 'Welcome, $short…!',
      );
    } catch (e) {
      if (!mounted) return;
      _showResult(
          success: false, title: 'Check-in failed', message: friendlyError(e));
    }
  }

  void _showResult(
      {required bool success, required String title, required String message}) {
    final scheme = Theme.of(context).colorScheme;
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                success ? Icons.check_circle_rounded : Icons.error_rounded,
                size: 64,
                color: success ? AppTheme.success : scheme.error,
              ),
              const SizedBox(height: 12),
              Text(title,
                  style: Theme.of(ctx)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Scan next'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickEvent() async {
    final events = await _eventRepo.watchUpcoming().first;
    if (!mounted) return;
    final picked = await showModalBottomSheet<_EventPick>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Choose event to check in',
                  style: Theme.of(ctx)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
            ),
            for (final e in events)
              ListTile(
                title: Text(e.title),
                subtitle: Text(
                    '${e.checkedInCount} checked in · ${e.participantsCount} registered'),
                onTap: () => Navigator.pop(ctx, _EventPick(e.id, e.title)),
              ),
          ],
        ),
      ),
    );
    if (picked != null) {
      setState(() {
        _selectedEventId = picked.id;
        _selectedEventTitle = picked.title;
      });
      _ensureCamera();
    }
  }

  Future<void> _manualEntry() async {
    final ctrl = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Manual ticket code'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'EV1.…'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('Check in')),
        ],
      ),
    );
    if (code != null && code.isNotEmpty && _selectedEventId != null) {
      await _checkIn(code);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Check-in')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickEvent,
                    icon: const Icon(Icons.event_rounded),
                    label: Text(
                      _selectedEventTitle ?? 'Select event',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Manual entry',
                  onPressed: _selectedEventId == null ? null : _manualEntry,
                  icon: const Icon(Icons.keyboard_rounded),
                ),
                IconButton(
                  tooltip: 'Toggle torch',
                  onPressed: _camera == null
                      ? null
                      : () async {
                          await _camera!.toggleTorch();
                          if (mounted) setState(() => _torchOn = !_torchOn);
                        },
                  icon: Icon(_torchOn
                      ? Icons.flash_on_rounded
                      : Icons.flash_off_rounded),
                ),
              ],
            ),
          ),
          Expanded(
            child: _selectedEventId == null
                ? EmptyState(
                    icon: Icons.qr_code_scanner_rounded,
                    title: 'Select an event first',
                    message:
                        'Then point the camera at the participant’s QR ticket.',
                  )
                : Stack(
                    alignment: Alignment.center,
                    children: [
                      MobileScanner(
                        controller: _camera,
                        onDetect: _onDetect,
                      ),
                      IgnorePointer(
                        child: Container(
                          width: 260,
                          height: 260,
                          decoration: BoxDecoration(
                            border: Border.all(
                                color: theme.colorScheme.primary, width: 3),
                            borderRadius: BorderRadius.circular(24),
                          ),
                        ),
                      ),
                      if (_processing)
                        Container(
                          color: Colors.black38,
                          child: const Center(
                              child: LoadingView(hint: 'Checking in…')),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _EventPick {
  const _EventPick(this.id, this.title);
  final String id;
  final String title;
}

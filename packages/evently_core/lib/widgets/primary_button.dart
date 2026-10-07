import 'package:flutter/material.dart';

/// Filled button with a built-in busy state so async actions show progress
/// without every screen reimplementing it.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.busy = false,
    this.expand = false,
    this.destructive = false,
  });

  final String label;
  final Future<void> Function()? onPressed;
  final IconData? icon;
  final bool busy;
  final bool expand;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = onPressed != null && !busy;

    final button = FilledButton.icon(
      style: FilledButton.styleFrom(
        backgroundColor: destructive ? scheme.error : null,
        foregroundColor: destructive ? scheme.onError : null,
      ),
      onPressed: enabled
          ? () async {
              try {
                await onPressed!();
              } finally {
                if (context.mounted) FocusScope.of(context).unfocus();
              }
            }
          : null,
      icon: busy
          ? SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: destructive ? scheme.onError : scheme.onPrimary,
              ),
            )
          : Icon(icon),
      label: Text(label),
    );

    if (!expand) return button;
    return SizedBox(width: double.infinity, child: button);
  }
}

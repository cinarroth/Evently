import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'empty_state.dart';
import 'error_state.dart';

/// Full-screen centered progress indicator with an optional hint.
class LoadingView extends StatelessWidget {
  const LoadingView({super.key, this.hint});

  final String? hint;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          if (hint != null) ...[
            const SizedBox(height: 16),
            Text(hint!, style: Theme.of(context).textTheme.bodySmall),
          ],
        ],
      ),
    );
  }
}

/// Maps the three stream states (data / empty / error) onto widgets, with
/// pull-to-refresh built in.
class StreamStateView<T> extends StatelessWidget {
  const StreamStateView({
    super.key,
    required this.snapshot,
    required this.builder,
    required this.emptyIcon,
    required this.emptyTitle,
    this.emptyMessage,
    this.onRefresh,
    this.emptyActionLabel,
    this.onEmptyAction,
  });

  final AsyncSnapshot<T> snapshot;
  final Widget Function(BuildContext, T) builder;
  final IconData emptyIcon;
  final String emptyTitle;
  final String? emptyMessage;
  final Future<void> Function()? onRefresh;
  final String? emptyActionLabel;
  final VoidCallback? onEmptyAction;

  @override
  Widget build(BuildContext context) {
    Widget content;
    if (snapshot.hasError) {
      content = ErrorState(message: '${snapshot.error}', onRetry: onRefresh);
    } else if (!snapshot.hasData) {
      content = const LoadingView();
    } else {
      final data = snapshot.data as T;
      final isEmpty = data is List && data.isEmpty;
      content = isEmpty
          ? EmptyState(
              icon: emptyIcon,
              title: emptyTitle,
              message: emptyMessage,
              actionLabel: emptyActionLabel,
              onAction: onEmptyAction,
            )
          : builder(context, data);
    }

    if (onRefresh == null) return content;
    return RefreshIndicator(onRefresh: onRefresh!, child: content);
  }
}

/// Standard confirmation dialog for destructive actions. Returns true when
/// the user confirmed.
Future<bool> confirmDestructive(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Delete',
}) async {
  final scheme = Theme.of(context).colorScheme;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: scheme.error),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

/// Shows a snackbar with friendly [error] copy.
void showErrorSnackBar(BuildContext context, Object error) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text('$error'),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Theme.of(context).colorScheme.errorContainer,
      ),
    );
  SystemSound.play(SystemSoundType.alert);
}

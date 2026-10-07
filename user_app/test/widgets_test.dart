import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:evently_core/evently_core.dart';

Widget _wrap(Widget child) => MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(body: child),
    );

void main() {
  group('ParticipantsBadge', () {
    testWidgets('shows remaining spots', (tester) async {
      await tester.pumpWidget(
          _wrap(const ParticipantsBadge(registered: 4, capacity: 10)));
      expect(find.text('6 / 10 left'), findsOneWidget);
    });

    testWidgets('shows Full when capacity reached', (tester) async {
      await tester.pumpWidget(
          _wrap(const ParticipantsBadge(registered: 10, capacity: 10)));
      expect(find.text('Full'), findsOneWidget);
    });
  });

  group('StatusChip', () {
    testWidgets('renders each status label', (tester) async {
      for (final status in EventStatus.values) {
        await tester.pumpWidget(_wrap(StatusChip(status: status)));
        expect(find.text(status.wire), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      }
    });
  });

  group('EmptyState', () {
    testWidgets('renders title, message and action', (tester) async {
      var tapped = false;
      await tester.pumpWidget(_wrap(EmptyState(
        icon: Icons.inbox,
        title: 'Nothing here',
        message: 'Come back later',
        actionLabel: 'Refresh',
        onAction: () => tapped = true,
      )));

      expect(find.text('Nothing here'), findsOneWidget);
      expect(find.text('Come back later'), findsOneWidget);

      await tester.tap(find.text('Refresh'));
      expect(tapped, isTrue);
    });
  });

  group('PrimaryButton', () {
    testWidgets('disabled while busy', (tester) async {
      var pressed = false;
      await tester.pumpWidget(_wrap(PrimaryButton(
        label: 'Register',
        busy: true,
        onPressed: () async => pressed = true,
      )));

      await tester.tap(find.text('Register'), warnIfMissed: false);
      await tester.pump();
      expect(pressed, isFalse);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('invokes callback when enabled', (tester) async {
      var pressed = false;
      await tester.pumpWidget(_wrap(PrimaryButton(
        label: 'Register',
        onPressed: () async => pressed = true,
      )));

      await tester.tap(find.text('Register'));
      await tester.pumpAndSettle();
      expect(pressed, isTrue);
    });
  });
}

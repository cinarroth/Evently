import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:evently_core/evently_core.dart';

Widget _wrap(Widget child) => MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(body: child),
    );

void main() {
  group('Event model in admin contexts', () {
    final event = Event(
      id: 'e1',
      title: 'Launch Night',
      description: 'Big celebration',
      coverImageUrl: null,
      location: 'Main Hall',
      startAt: DateTime(2026, 10, 20, 18),
      endAt: DateTime(2026, 10, 20, 21),
      capacity: 100,
      participantsCount: 73,
      checkedInCount: 40,
      status: EventStatus.ongoing,
      category: 'community',
      organizerId: 'admin',
      createdAt: DateTime(2026, 10, 1),
      updatedAt: DateTime(2026, 10, 1),
    );

    test('capacity math used by the dashboard', () {
      expect(event.spotsAvailable, 27);
      expect(event.isPast, isFalse);
      expect(event.status, EventStatus.ongoing);
    });

    test('editableMap never exposes server-owned fields', () {
      final map = event.editableMap();
      expect(map.containsKey('participantsCount'), isFalse);
      expect(map.containsKey('checkedInCount'), isFalse);
      expect(map.containsKey('status'), isFalse);
      expect(map.containsKey('qrToken'), isFalse);
    });
  });

  group('StatusChip', () {
    testWidgets('renders canceled state for admin list rows', (tester) async {
      await tester
          .pumpWidget(_wrap(const StatusChip(status: EventStatus.canceled)));
      expect(find.text('CANCELED'), findsOneWidget);
    });
  });

  group('PrimaryButton destructive', () {
    testWidgets('renders error styling without crashing', (tester) async {
      await tester.pumpWidget(_wrap(PrimaryButton(
        label: 'Delete event',
        icon: Icons.delete_outline,
        destructive: true,
        onPressed: () async {},
      )));
      expect(find.text('Delete event'), findsOneWidget);
    });
  });
}

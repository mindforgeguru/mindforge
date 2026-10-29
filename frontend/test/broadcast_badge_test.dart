import 'package:flutter_test/flutter_test.dart';

import 'package:mindforge/core/providers/badge_provider.dart';

void main() {
  final seen = DateTime(2026, 10, 29, 9);
  final later = DateTime(2026, 10, 29, 10);

  // #9: a teacher's own broadcast lit their Announcements badge.
  test("the sender's own broadcast is never new to them", () {
    expect(
        isUnseenBroadcast(
            createdAt: later, senderId: 11, viewerId: 11, lastSeen: seen),
        isFalse);
    expect(
        isUnseenBroadcast(
            createdAt: later, senderId: 11, viewerId: 11, lastSeen: null),
        isFalse);
  });

  test("another sender's broadcast is new until seen", () {
    expect(
        isUnseenBroadcast(
            createdAt: later, senderId: 2, viewerId: 11, lastSeen: seen),
        isTrue);
    expect(
        isUnseenBroadcast(
            createdAt: seen, senderId: 2, viewerId: 11, lastSeen: later),
        isFalse);
  });
}

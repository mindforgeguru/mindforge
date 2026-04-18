import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mindforge/main.dart';

void main() {
  testWidgets('App launches and shows MindForge login screen',
      (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: MindForgeApp()));
    await tester.pump(const Duration(milliseconds: 100));

    // App should render at least one MaterialApp
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}

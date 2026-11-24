import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mindforge/core/widgets/school_title_block.dart';

Widget _host(String name, double width) => MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            child: SchoolTitleBlock(
                name: name, titleFs: 24, taglineFs: 14, gap: 3),
          ),
        ),
      ),
    );

void main() {
  // A wrapped school name pushed the tagline into the header's avatar.
  testWidgets('a name that fits keeps the tagline', (tester) async {
    await tester.pumpWidget(_host('Sunrise', 400));
    expect(find.text('AI Assisted Learning'), findsOneWidget);
  });

  testWidgets('a name that wraps drops the tagline', (tester) async {
    await tester.pumpWidget(_host('Sunrise Public School', 220));
    expect(find.text('AI Assisted Learning'), findsNothing);
    expect(find.text('Sunrise Public School'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

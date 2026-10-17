import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Every icon-only button needs words for a screen reader.
///
/// An IconButton draws a glyph and nothing else. Without a `tooltip` (or a
/// `semanticLabel` on its icon) VoiceOver and TalkBack announce it as just
/// "button" — the logout button, the MPIN show/hide toggle, the calendar
/// arrows. On 2026-10-15, 46 of the app's 71 icon buttons had no label.
///
/// A source scan rather than a widget test: the buttons are spread over every
/// role's screens, and pumping them all would need the whole app's providers.
/// The rule it enforces is simple enough to read off the source.
void main() {
  test('every IconButton in lib/ has a tooltip or a semantic label', () {
    final unlabelled = <String>[];
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'));
    for (final file in files) {
      final src = file.readAsStringSync();
      // `IconButton(` and its named constructors, but not `IconButton.styleFrom(`.
      for (final m in RegExp(r'IconButton(\.(filled|filledTonal|outlined))?\(')
          .allMatches(src)) {
        var i = m.end, depth = 1;
        while (depth > 0 && i < src.length) {
          final c = src[i];
          if (c == '(') depth++;
          if (c == ')') depth--;
          i++;
        }
        final call = src.substring(m.start, i);
        if (!call.contains('tooltip') && !call.contains('semanticLabel')) {
          final line = '\n'.allMatches(src.substring(0, m.start)).length + 1;
          unlabelled.add('${file.path}:$line');
        }
      }
    }
    expect(unlabelled, isEmpty,
        reason: 'IconButtons with nothing for a screen reader to say — '
            'add a tooltip:\n${unlabelled.join('\n')}');
  });
}

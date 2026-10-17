import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mindforge/core/theme/app_theme.dart';
import 'package:mindforge/core/theme/brand_palette.dart';

/// Text has to be readable against the cards and the page behind it.
///
/// WCAG AA asks 4.5:1 for normal-size text, and nearly all of the app's text
/// is small (11–14 px). On 2026-10-16 the muted grey used for hints, dates and
/// empty-state lines was 2.5:1 on the page background, and the XP themes'
/// yellow and amber accents — drawn as text for every "See all →" link — were
/// 1.5–2.2:1: Tide Breeze's links were close to invisible.
double _contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void _expectReadable(String name, Color text) {
  for (final (bgName, bg) in [
    ('a card', AppColors.surface),
    ('the page background', AppColors.background),
  ]) {
    final ratio = _contrast(text, bg);
    expect(ratio, greaterThanOrEqualTo(4.5),
        reason: '$name on $bgName is ${ratio.toStringAsFixed(2)}:1');
  }
}

void main() {
  test('fixed text colours are readable on cards and the page', () {
    _expectReadable('textPrimary', AppColors.textPrimary);
    _expectReadable('textSecondary', AppColors.textSecondary);
    _expectReadable('textMuted', AppColors.textMuted);
    _expectReadable('success', AppColors.success);
    _expectReadable('warning', AppColors.warning);
    _expectReadable('error', AppColors.error);
  });

  for (final p in BrandPalettes.all) {
    test('${p.name}: the colours drawn as text are readable', () {
      _expectReadable('${p.id}.primary', p.primary);
      _expectReadable('${p.id}.accentText', p.accentText);
      _expectReadable('${p.id}.secondaryText', p.secondaryText);
    });
  }

  // The theme's accent and secondary are fill colours — bars, chips, dots —
  // and several themes' are pale. Text in those hues goes through
  // `accentText` / `secondaryText`, which every palette keeps dark enough.
  test('no text style uses a theme\'s accent or secondary fill colour', () {
    final offenders = <String>[];
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'));
    // `AppColors.accent`, and a palette read directly (`palette.accentDark`).
    final use = RegExp(r'color:\s*(AppColors|\w*[pP]alette)\.'
        r'(accent|secondary)(Light|Dark)?(?![\w.])');
    for (final file in files) {
      final src = file.readAsStringSync();
      for (final m in use.allMatches(src)) {
        // Walk back to the call this `color:` argument belongs to.
        var i = m.start - 1, depth = 0;
        while (i >= 0) {
          final c = src[i];
          if (c == ')') depth++;
          if (c == '(') {
            if (depth == 0) break;
            depth--;
          }
          i--;
        }
        final callee = RegExp(r'(\w+)\s*$').firstMatch(src.substring(0, i));
        final name = callee?.group(1);
        if (name == 'TextStyle' || name == 'poppins' || name == 'copyWith') {
          final line = '\n'.allMatches(src.substring(0, m.start)).length + 1;
          offenders.add('${file.path}:$line');
        }
      }
    }
    expect(offenders, isEmpty,
        reason: 'Text drawn in a fill colour — use AppColors.accentText or '
            'AppColors.secondaryText:\n${offenders.join('\n')}');
  });

  // App bars sit on the theme's dark primary. The page's text colours are
  // for light grounds — on 2026-10-16 the test screen's "1/3 answered" was
  // dark blue on navy.
  test('app bars on the dark default ground use no light-ground text colour',
      () {
    final offenders = <String>[];
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'));
    final dark = RegExp(r'AppColors\.text(Primary|Secondary|Muted)\b');
    for (final file in files) {
      final src = file.readAsStringSync();
      for (final m in RegExp(r'\bAppBar\(').allMatches(src)) {
        var i = m.end, depth = 1;
        while (depth > 0 && i < src.length) {
          if (src[i] == '(') depth++;
          if (src[i] == ')') depth--;
          i++;
        }
        var call = src.substring(m.start, i);
        // An app bar given its own background is checked by eye.
        if (call.contains('backgroundColor:')) continue;
        // A dropdown shows its chosen item on the bar itself, in that item's
        // own (dark, menu) style unless it builds a separate one for the bar:
        // the admin's Fees year was navy on navy, invisible.
        if (call.contains('DropdownButton') &&
            !call.contains('selectedItemBuilder')) {
          final line = '\n'.allMatches(src.substring(0, m.start)).length + 1;
          offenders.add('${file.path}:$line (dropdown without selectedItemBuilder)');
        }
        // Dropdown items draw on the menu's white sheet, not on the bar.
        // Blanked rather than cut, so offsets (and line numbers) still hold.
        for (var at = call.indexOf('DropdownMenuItem(');
            at >= 0;
            at = call.indexOf('DropdownMenuItem(', at + 1)) {
          var j = at + 'DropdownMenuItem('.length, depth = 1;
          while (depth > 0 && j < call.length) {
            if (call[j] == '(') depth++;
            if (call[j] == ')') depth--;
            j++;
          }
          call = call.replaceRange(at, j, ' ' * (j - at));
        }
        for (final d in dark.allMatches(call)) {
          final line =
              '\n'.allMatches(src.substring(0, m.start + d.start)).length + 1;
          offenders.add('${file.path}:$line');
        }
      }
    }
    expect(offenders, isEmpty,
        reason: 'Dark text on a dark app bar:\n${offenders.join('\n')}');
  });
}

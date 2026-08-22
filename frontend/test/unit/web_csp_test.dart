import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The web build's Content-Security-Policy is the app's main defence for the
/// browser: it constrains what can execute, where the page can talk to, and who
/// can frame it. Flutter's canvas rendering already keeps most XSS off the
/// table (there is no innerHTML sink), so the CSP is what remains — and it is a
/// single meta tag one careless edit could gut. These tests pin the directives
/// that actually matter, so weakening them fails CI instead of silently
/// shipping.
///
/// They intentionally do NOT forbid 'unsafe-inline'/'unsafe-eval'/blob: in
/// script-src: Flutter web's bootstrap (canvaskit, dart2js, the service worker)
/// requires them. Locking those down is a framework-level change, not a config
/// slip, so pinning them here would only produce false alarms.
void main() {
  late String csp;

  setUpAll(() {
    final html = File('web/index.html').readAsStringSync();
    final match = RegExp(
      r'''http-equiv="Content-Security-Policy"\s+content="([^"]*)"''',
    ).firstMatch(html);
    expect(match, isNotNull, reason: 'web/index.html has no CSP meta tag');
    csp = match!.group(1)!;
  });

  String directive(String name) {
    final m = RegExp('(?:^|;)\\s*$name\\s+([^;]*)').firstMatch(csp);
    return m?.group(1)?.trim() ?? '';
  }

  test('default-src is self, not a wildcard', () {
    expect(directive('default-src'), "'self'");
  });

  test('frame-ancestors none — the page cannot be framed (clickjacking)', () {
    // The one directive iframes obey regardless of the meta-vs-header caveat
    // for framing; 'none' means no site may embed the app.
    expect(directive('frame-ancestors'), "'none'");
  });

  test('base-uri and form-action are locked to self', () {
    // base-uri 'self' stops an injected <base> from rewriting every relative
    // URL; form-action 'self' stops a form from posting credentials off-site.
    expect(directive('base-uri'), "'self'");
    expect(directive('form-action'), "'self'");
  });

  test('no directive is opened to a bare wildcard', () {
    // A lone `*` in any fetch directive would defeat the point. Scoped hosts
    // (https://api.mindforge.guru) are fine; `*` / `* ` / `*;` are not.
    expect(RegExp(r'''(?:^|\s)\*(?:\s|;|$)''').hasMatch(csp), isFalse,
        reason: 'CSP contains a bare wildcard source: $csp');
  });

  test('connect-src does not allow http/ws to an arbitrary host', () {
    // The app should only reach its own API origins. Guard against someone
    // pasting a `http://*` or a plaintext third-party host in here.
    final connect = directive('connect-src');
    expect(connect.contains('*'), isFalse, reason: connect);
    // The production API must remain reachable, or the shipped app breaks.
    expect(connect.contains('https://api.mindforge.guru'), isTrue);
  });

  test('script-src does not allow a remote wildcard CDN', () {
    // 'unsafe-inline'/'unsafe-eval'/blob: are required by Flutter and allowed;
    // a wildcard remote origin (https://*) would let an attacker host script.
    final script = directive('script-src');
    expect(RegExp(r'https://\*').hasMatch(script), isFalse, reason: script);
  });
}

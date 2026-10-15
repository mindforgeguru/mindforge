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

  test('frame-ancestors none is also declared in the meta tag', () {
    // Browsers IGNORE frame-ancestors in a meta tag (CSP3 §6.4.2; Chrome logs
    // "ignored when delivered via a <meta> element"). It is kept here only as
    // documentation of intent — the protection that works is the response
    // header in web/_headers, pinned below.
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

  test('img-src allows every http(s) API origin that connect-src allows', () {
    // Logos and avatars are served by the API's /api/media proxy, so any API
    // origin the app talks to must also be allowed to serve images. img-src
    // once listed only the production API, which silently blocked every school
    // logo and avatar on a local web build (http://localhost:8000).
    final img = directive('img-src').split(RegExp(r'\s+'));
    final apiOrigins = directive('connect-src')
        .split(RegExp(r'\s+'))
        .where((s) => s.startsWith('http://') || s.startsWith('https://'))
        .where((s) => !s.contains('gstatic.com'));
    for (final origin in apiOrigins) {
      expect(img, contains(origin), reason: 'img-src is missing $origin');
    }
  });

  test('script-src does not allow a remote wildcard CDN', () {
    // 'unsafe-inline'/'unsafe-eval'/blob: are required by Flutter and allowed;
    // a wildcard remote origin (https://*) would let an attacker host script.
    final script = directive('script-src');
    expect(RegExp(r'https://\*').hasMatch(script), isFalse, reason: script);
  });

  group('web/_headers (Netlify) — framing has to be refused by a header', () {
    // Production serves the web build from Netlify, which applies this file to
    // every response. Without it the site sent no X-Frame-Options and no CSP
    // header, so any page could embed the login screen in an iframe
    // (clickjacking) — the meta tag's frame-ancestors does nothing.
    late Map<String, String> headers;

    setUpAll(() {
      final file = File('web/_headers');
      expect(file.existsSync(), isTrue, reason: 'web/_headers is missing');
      final lines = file.readAsLinesSync();
      final start = lines.indexWhere((l) => l.trim() == '/*');
      expect(start, isNot(-1), reason: 'web/_headers has no `/*` block');
      headers = {};
      for (final line in lines.skip(start + 1)) {
        if (line.trim().isEmpty || !line.startsWith(RegExp(r'\s'))) break;
        final i = line.indexOf(':');
        headers[line.substring(0, i).trim().toLowerCase()] =
            line.substring(i + 1).trim();
      }
    });

    test('X-Frame-Options DENY on every path', () {
      expect(headers['x-frame-options'], 'DENY');
    });

    test("a CSP header with frame-ancestors 'none'", () {
      expect(headers['content-security-policy'], contains("frame-ancestors 'none'"));
    });

    test('nosniff on every path', () {
      expect(headers['x-content-type-options'], 'nosniff');
    });
  });
}

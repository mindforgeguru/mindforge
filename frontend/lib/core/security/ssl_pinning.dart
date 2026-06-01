import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';

/// SSL Certificate Pinning for api.mindforge.guru
///
/// ── How it works ─────────────────────────────────────────────────────────────
/// dio calls [IOHttpClientAdapter.validateCertificate] ONLY after the OS /
/// SecurityContext (and badCertificateCallback) have already validated the full
/// chain — trusted root, intermediate, hostname, and expiry. So this callback
/// only ever receives an already-OS-trusted leaf certificate. We add ONE extra
/// constraint on top of that: the leaf must be issued by our CA, Let's Encrypt.
///
/// This is **CA pinning**, deliberately chosen over leaf-fingerprint pinning:
///   • It survives the ~90-day Let's Encrypt leaf renewal that Railway performs
///     automatically. Leaf-fingerprint pinning locked every app build out of
///     the API on 2026-05-29 when the leaf rotated (web was unaffected because
///     browsers trust the CA chain rather than a pinned leaf). CA pinning does
///     not have that failure mode.
///   • It still defends against the threat pinning exists for: an OS-trusted
///     cert MIS-ISSUED for our host by a *different* CA. Such a cert passes the
///     OS chain check but fails the issuer test here and is rejected.
///   • It is safe against forged-issuer self-signed certs: those never pass the
///     OS chain validation, so this callback is never reached for them.
///
/// The known-good leaf fingerprints below are kept as a fast path / audit trail
/// of certs we've explicitly seen; they are not required for a connection to
/// succeed (the issuer check covers all valid renewals).
///
/// ── If we ever move off Let's Encrypt ────────────────────────────────────────
/// Update [_trustedIssuerOrgs] to the new CA's organisation name. To inspect the
/// current issuer + leaf fingerprint:
///
///   echo | openssl s_client -connect api.mindforge.guru:443 2>/dev/null \
///     | openssl x509 -noout -issuer -fingerprint -sha256
/// ────────────────────────────────────────────────────────────────────────────

/// Issuer organisation(s) we accept for [_pinnedHost], matched case-insensitively
/// against the leaf's issuer DN with apostrophes stripped (so both "Let's
/// Encrypt" and "Lets Encrypt" match regardless of DN formatting).
const _trustedIssuerOrgs = <String>{
  'lets encrypt',
};

/// Known-good leaf fingerprints (SHA-256 of DER). Fast-path + audit trail only;
/// a valid Let's Encrypt renewal not listed here is still accepted via the
/// issuer check, by design.
const _knownLeafFingerprints = <String>{
  // Current leaf — expires 2026-08-27 (issued 2026-05-29, via Let's Encrypt YE1).
  '1cc35babfed16ce0ae3cf524d9b5fe4aed52ebeebfd7242aaba3433504ceeb46',
  // Previous leaf — expired 2026-06-28 (issued 2026-03-30, via E8).
  '2489dccbd08cea6663085e5c809239c84b818020389e45086c2e544a716e26f7',
  // Older leaf (deep backup).
  '9b4febcb02f1649d17f95a3bf08509364beebf17fe046706e1463de5fb8ec413',
};

const _pinnedHost = 'api.mindforge.guru';

String _normalizeDn(String dn) =>
    dn.toLowerCase().replaceAll("'", '').replaceAll('’', '');

/// Applies certificate pinning to a [IOHttpClientAdapter].
///
/// Pinning is skipped in debug mode so developers can use Charles/proxyman
/// for local inspection. Always active in profile and release builds.
void applySSLPinning(IOHttpClientAdapter adapter) {
  adapter.validateCertificate = (X509Certificate? cert, String host, int port) {
    // Only pin our own API host — let other connections (fonts, etc.) through.
    if (host != _pinnedHost) return true;

    // Skip pinning in debug mode to allow local proxy inspection.
    if (kDebugMode) return true;

    if (cert == null) return false;

    // Fast path: a leaf we've explicitly recorded.
    final fingerprint = sha256.convert(cert.der).toString();
    if (_knownLeafFingerprints.contains(fingerprint)) return true;

    // Resilient path: any leaf issued by our CA. The chain is already
    // OS-validated at this point, so this only accepts genuinely trusted certs
    // that are *also* from Let's Encrypt — and survives leaf renewals.
    final issuer = _normalizeDn(cert.issuer);
    if (_trustedIssuerOrgs.any(issuer.contains)) return true;

    // Log mismatch so it surfaces in crash reports / logs.
    debugPrint(
      '[SSL Pinning] REJECTED certificate for $host\n'
      '  fingerprint: $fingerprint\n'
      '  issuer:      ${cert.issuer}',
    );
    return false;
  };
}

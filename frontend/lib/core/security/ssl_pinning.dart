import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';

/// SSL Certificate Pinning for api.mindforge.guru
///
/// How it works:
///   After the OS validates the certificate chain normally (CA trust, expiry,
///   hostname), our callback additionally checks that the leaf certificate's
///   SHA-256 fingerprint matches one of the pinned values below.
///
/// ── Certificate rotation guide ──────────────────────────────────────────────
/// The leaf cert (Let's Encrypt) auto-renews every ~90 days on Railway.
/// Current leaf cert expires: 2026-06-28
///
/// When the cert renews, run this command and update [_pinnedFingerprints]:
///
///   echo | openssl s_client -connect api.mindforge.guru:443 2>/dev/null \
///     | openssl x509 -noout -fingerprint -sha256 \
///     | tr -d ':' | tr '[:upper:]' '[:lower:]'
///
/// Keep the OLD fingerprint in the set for one release cycle as a backup
/// so users on the previous app version aren't immediately locked out.
///
/// Intermediate CA fingerprint is included as a stable backup — it changes
/// far less frequently than the leaf cert. Issuing intermediate may also
/// change between cert rotations (e.g. R12 → E8 when Railway switches from
/// RSA to ECDSA), so list known intermediates here too.
/// ────────────────────────────────────────────────────────────────────────────
const _pinnedFingerprints = {
  // Leaf cert — current, expires 2026-06-28 (issued 2026-03-30, ECDSA via E8)
  '2489dccbd08cea6663085e5c809239c84b818020389e45086c2e544a716e26f7',
  // Let's Encrypt E8 intermediate CA (current issuer)
  '83624fd338c8d9b023c18a67cb7a9c0519da43d11775b4c6cbdad45c3d997c52',
  // Previous leaf (kept one release cycle for older app installs)
  '9b4febcb02f1649d17f95a3bf08509364beebf17fe046706e1463de5fb8ec413',
  // Let's Encrypt R12 intermediate CA (previous RSA chain)
  '131fce7784016899a5a00203a9efc80f18ebbd75580717edc1553580930836ec',
};

const _pinnedHost = 'api.mindforge.guru';

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

    final fingerprint = sha256.convert(cert.der).toString();
    final trusted = _pinnedFingerprints.contains(fingerprint);

    if (!trusted) {
      // Log mismatch so it shows up in crash reports / logs.
      debugPrint(
        '[SSL Pinning] REJECTED certificate for $host\n'
        '  Got:      $fingerprint\n'
        '  Expected: ${_pinnedFingerprints.join(' | ')}',
      );
    }

    return trusted;
  };
}

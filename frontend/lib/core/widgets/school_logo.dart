import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/school_logo_provider.dart';

/// Shows the admin-uploaded school logo, falling back to the bundled MindForge
/// logo when the school hasn't uploaded one (or it hasn't loaded yet).
///
/// Drop-in replacement for `Image.asset('assets/images/logo.png', fit: ...)` —
/// callers keep their existing sizing/decoration wrapper and only swap the
/// image. The school logo is resolved once from [currentSchoolLogoProvider]
/// (shared across the whole app, so this is a single network fetch no matter
/// how many badges are on screen).
///
/// Pass [logoUrl] to override the resolved logo. The login screen uses this:
/// the school is chosen in a picker *before* the user is authenticated, so
/// [currentSchoolLogoProvider] (which keys off the signed-in user's school)
/// can't know it yet — the screen passes the picked school's logo directly.
class SchoolLogo extends ConsumerWidget {
  final BoxFit fit;
  final String? logoUrl;

  const SchoolLogo({super.key, this.fit = BoxFit.contain, this.logoUrl});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // When an explicit URL is given, `??` short-circuits and the provider is
    // never watched — correct for the pre-auth login screen.
    final url = logoUrl ?? ref.watch(currentSchoolLogoProvider).valueOrNull;

    final fallback = Image.asset('assets/images/logo.png', fit: fit);
    if (url == null || url.isEmpty) return fallback;

    return CachedNetworkImage(
      imageUrl: url,
      fit: fit,
      // Show the MindForge logo while the school logo loads and if it fails,
      // so there's never a blank or broken-image gap.
      placeholder: (_, __) => fallback,
      errorWidget: (_, __, ___) => fallback,
    );
  }
}
